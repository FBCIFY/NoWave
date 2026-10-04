"""Prepare a configured real region, without implicit regional network downloads."""
import argparse
from contextlib import closing
from itertools import chain
import json
from pathlib import Path
import sys

from region_config import resolve_region

ROOT = Path(__file__).resolve().parents[1]


def prepare(region, sources_path, catalog_path, output, cache, resolution=100, block_size=512):
    if region['id'] == 'cassis':
        raise ValueError('Cassis must always use prepare_cassis.py')
    # Also reject aliases/symlinks and another region targeting the Cassis tree.
    protected = (ROOT / 'data' / 'cassis').resolve()
    for path in (output, cache):
        if path.resolve().is_relative_to(protected) or protected.is_relative_to(path.resolve()):
            raise ValueError('Regional output/cache must not overlap cartography/data/cassis')
    from pipeline_io import staged_generation, publish_generation
    with staged_generation(output) as staging:
        manifest = _prepare_generation(region, sources_path, catalog_path, staging, cache,
                                       resolution, block_size)
        return publish_generation(output, staging, manifest)


def _prepare_generation(region, sources_path, catalog_path, output, cache, resolution, block_size):
    from shapely.geometry import box
    from pipeline_io import atomic_json, checked_asset, geometry_file, feature, write_collection, digest
    from coastal_geometry import coastal_zone, polygonal
    from regional_osm import extract_pbf, ingest, coast_from_inventory, features_in_zone
    from regional_bathymetry import build_field, contours

    sources = json.loads(sources_path.read_text())
    if sources.get('schema') != 1:
        raise ValueError('Sources schema=1 required')
    # Scope is a sourced polygon selecting French coastline, including small islands.
    # Its boundary is NEVER emitted as coastline or used for a coastal buffer.
    paths = {name: checked_asset(sources[name], sources_path.parent) for name in ('osm', 'land', 'coast_scope')}
    output.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    extent = box(*region['bbox'])
    land = polygonal(geometry_file(paths['land']).intersection(extent))
    scope = polygonal(geometry_file(paths['coast_scope']).intersection(extent))
    if land.geom_type not in ('Polygon', 'MultiPolygon') or scope.geom_type not in ('Polygon', 'MultiPolygon'):
        raise ValueError('Land and coast scope must be polygonal')
    extracted = extract_pbf(paths['osm'], region['bbox'], cache)
    with closing(ingest(extracted, cache / 'inventory.sqlite', region['bbox'],
                {'source_sha256': sources['osm']['sha256'], 'retrieved_at': sources['osm']['date']}, cache)) as db:
        coast = coast_from_inventory(db, scope)
        sea, useful = coastal_zone(coast, land, region['bbox'], region['coverage']['sea_buffer_nm'])
        if sea.is_empty:
            raise ValueError('Empty marine coverage')
        atomic_json(output / 'coverage.geojson', feature('coverage', sea, source='OSM coastline metric buffer'))
        atomic_json(output / 'water.geojson', feature('water', polygonal(extent.difference(land)),
                    source=sources['land']['source'], license=sources['land']['license']))
        bathymetry = build_field(catalog_path, output / 'coverage.geojson', cache / 'bathymetry', resolution, block_size)
        write_collection(output / 'features.geojson', chain(
            [feature('land', land, source=sources['land']['source'], license=sources['land']['license'],
                     source_sha256=sources['land']['sha256'], date=sources['land']['date'])],
            features_in_zone(db, useful, land, coast), contours(bathymetry)))
        # Audit is streamed too: unsupported objects never acquire guessed types.
        audit = ({'type': 'Feature', 'geometry': None, 'properties': {'osm_id': i, 'osm_tags': json.loads(t), 'reason': r}}
                 for i, t, r in db.execute('SELECT id,tags,reason FROM skipped ORDER BY id'))
        write_collection(output / 'osm-not-rendered.geojson', audit)
    atomic_json(output / 'bathymetry.json', bathymetry)
    west, south, east, north = region['bbox']
    manifest = {'schema': 1, 'mode': 'REGION_REAL', 'region': region['id'], 'bbox': region['bbox'],
                'center': region['center'], 'zoom': region['zoom'], 'sources': sources,
                'coordinates': [[west, north], [east, north], [east, south], [west, south]],
                'bathymetry': bathymetry, 'coverage': {**region['coverage'], 'projection': 'EPSG:2154',
                    'land_buffer_m': 3000, 'complete': False},
                'features_sha256': digest(output / 'features.geojson'),
                'warning': 'NoWave n’est pas une carte officielle de navigation.'}
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', default='cassis')
    parser.add_argument('--sources', type=Path, help='Pinned OSM PBF, land and French coast scope catalog')
    parser.add_argument('--bathymetry-catalog', type=Path)
    parser.add_argument('--cache', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--resolution', type=float, default=None)
    parser.add_argument('--block-size', type=int, default=None)
    parser.add_argument('--offline', action='store_true', help='Cassis cached acquisition; regional ingest is always local')
    args = parser.parse_args()
    region = resolve_region(args.region)
    if region['id'] == 'cassis':
        # Cassis has a validated small-area survey interpolation profile.
        # Keep its numerical recipe and artifacts stable during the regional rollout.
        forbidden = [flag for flag, value in (
            ('--sources', args.sources), ('--bathymetry-catalog', args.bathymetry_catalog),
            ('--output', args.output), ('--resolution', args.resolution),
            ('--block-size', args.block_size)) if value is not None]
        if forbidden:
            parser.error('Cassis refuses regional options: ' + ', '.join(forbidden))
        import prepare_cassis
        command = ['prepare_cassis.py', '--region', str(ROOT / 'regions' / 'cassis.json')]
        if args.cache:
            command += ['--cache', str(args.cache)]
        if args.offline:
            command += ['--offline']
        sys.argv = command
        prepare_cassis.main()
        return
    if not args.sources or not args.bathymetry_catalog:
        parser.error('Regional pipeline requires --sources and --bathymetry-catalog; see FRANCE_MED_REAL.md')
    prepare(region, args.sources, args.bathymetry_catalog, args.output or ROOT / 'data' / region['id'],
            args.cache or Path.home() / '.cache' / 'nowave' / region['id'],
            100 if args.resolution is None else args.resolution,
            512 if args.block_size is None else args.block_size)


if __name__ == '__main__':
    main()
