"""Measure a published real region from its verified files and per-cell field."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sqlite3
from contextlib import closing

import numpy as np
import rasterio
from rasterio.windows import Window
from shapely import contains_xy, segmentize, set_precision
from shapely.geometry import box
from shapely.ops import transform

from coastal_geometry import TO_METRIC, TO_WGS84, line_buffer
from pipeline_io import atomic_json, checked_asset, current_generation, digest, geometry_file, iter_collection
from regional_osm import coast_from_inventory
from region_config import resolve_region

ROOT = Path(__file__).resolve().parents[1]


def audit(region, cache):
    generation = current_generation(ROOT / 'data' / region['id'])
    manifest = json.loads((generation / 'manifest.json').read_text())
    for name, sha in manifest['files_sha256'].items():
        if digest(generation / name) != sha:
            raise ValueError('Published file checksum differs: ' + name)
    sources = manifest['sources']
    # Sources use absolute paths in the locally produced catalogues.
    land = geometry_file(checked_asset(sources['land'], ROOT / 'regions'))
    scope = geometry_file(checked_asset(sources['coast_scope'], ROOT / 'regions'))
    checked_asset(sources['osm'], ROOT / 'regions')
    with closing(sqlite3.connect(f'file:{(cache / "inventory.sqlite").resolve()}?mode=ro', uri=True)) as db:
        coast = coast_from_inventory(db, scope)
    metric_coast = set_precision(transform(TO_METRIC, coast), .01)
    metric_land = set_precision(transform(TO_METRIC, land), .01)
    unclipped = line_buffer(metric_coast, region['coverage']['sea_buffer_nm'] * 1852).difference(metric_land)
    extent = transform(TO_METRIC, segmentize(box(*region['bbox']), .01))
    outside = unclipped.difference(extent).area
    if outside > 1:
        raise ValueError(f'Work bbox clips {outside / 1e6:.6f} km² of the marine buffer')
    coverage = transform(TO_METRIC, geometry_file(generation / 'coverage.geojson'))
    kinds, invalid, missing_icons = Counter(), 0, Counter()
    sprites = json.loads((ROOT / 'assets/sprite.json').read_text())
    for value in iter_collection(generation / 'features.geojson'):
        p = value['properties']
        kinds[p['kind']] += 1
        invalid += p.get('demo') is not False
        if p.get('icon') and p['icon'] not in sprites:
            missing_icons[p['icon']] += 1
    if invalid or missing_icons:
        raise ValueError(f'Invalid real provenance/sprites: {invalid}, {missing_icons}')
    excluded = sum(1 for _ in iter_collection(generation / 'osm-not-rendered.geojson', True))
    field = manifest['bathymetry']
    marine, known, zero, source_cells = 0, 0, 0, Counter()
    depth_min, depth_max = float('inf'), -float('inf')
    missing_by_lon = Counter()
    with rasterio.open(field['depth_vrt']) as src:
        for block in field['blocks']:
            col, row, size = block['col'], block['row'], block['size']
            depth, ids = src.read(window=Window(col, row, size, size))
            xx, yy = np.meshgrid(src.transform.c + (col + np.arange(size) + .5) * src.transform.a,
                                 src.transform.f + (row + np.arange(size) + .5) * src.transform.e)
            support = contains_xy(coverage, xx, yy)
            valid = np.isfinite(depth)
            product_ids = [p['source_id'] for p in field['products']]
            if (np.any(valid & ~support) or np.any(depth[valid] < 0)
                    or np.any(ids[~valid] != 0) or np.any(~np.isin(ids[valid], product_ids))):
                raise ValueError('Invalid depth support, sign or source ID')
            marine += int(support.sum())
            known += int(valid.sum())
            zero += int((valid & (depth == 0)).sum())
            for i, count in zip(*np.unique(ids[valid], return_counts=True)):
                source_cells[str(int(i))] += int(count)
            if valid.any():
                depth_min = min(depth_min, float(depth[valid].min()))
                depth_max = max(depth_max, float(depth[valid].max()))
            lon, _ = TO_WGS84(xx[support & ~valid], yy[support & ~valid])
            for bucket, count in zip(*np.unique(np.floor(lon * 10) / 10, return_counts=True)):
                missing_by_lon[f'{bucket:.1f}–{bucket + .1:.1f}'] += int(count)
    if known != field['valid_cells']:
        raise ValueError('Known cell count differs from manifest')
    def size(path):
        return sum(p.stat().st_size for p in path.rglob('*') if p.is_file()) if path.is_dir() else path.stat().st_size
    return dict(region=region['id'], generation_id=manifest['generation_id'],
        extent=dict(work_bbox=region['bbox'], sea_buffer_nm=region['coverage']['sea_buffer_nm'],
                    sea_buffer_m=region['coverage']['sea_buffer_nm'] * 1852,
                    unclipped_marine_bbox=list(transform(TO_WGS84, unclipped).bounds),
                    outside_work_bbox_km2=outside / 1e6, coast_km=metric_coast.length / 1000,
                    marine_area_km2=coverage.area / 1e6),
        osm=dict(counts=dict(sorted(kinds.items())), audited_not_rendered=excluded,
                 source_sha256=sources['osm']['sha256']),
        bathymetry=dict(resolution_m=field['resolution_m'], vertical_reference=field['vertical_reference'],
            marine_cells=marine, known_cells=known, nodata_cells=marine - known,
            known_percent=100 * known / marine, known_area_km2=known * field['resolution_m']**2 / 1e6,
            nodata_area_km2=(marine - known) * field['resolution_m']**2 / 1e6,
            source_cells=dict(source_cells), actual_zero_depth_cells=zero,
            min_depth_m=depth_min, max_depth_m=depth_max,
            nodata_longitude_buckets=dict(sorted(missing_by_lon.items()))),
        sizes_bytes=dict(prepared=size(generation), vector=size(ROOT / 'tiles/vector' / (region['id'] + '.mbtiles')),
                         bathymetry_tiles=size(ROOT / 'tiles/bathymetry' / region['id']), bathymetry_cache=size(Path(field['depth_vrt']).parent)),
        checksums=dict(features=manifest['features_sha256'], files=manifest['files_sha256']),
        limitations=['Cell-center area estimates at the processing resolution',
                     'Geometric coverage is not completeness of OSM objects or bathymetric surveys'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', default='france_med')
    parser.add_argument('--cache', type=Path, default=Path.home() / '.cache/nowave/france_med')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(resolve_region(args.region), args.cache)
    atomic_json(args.output, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
