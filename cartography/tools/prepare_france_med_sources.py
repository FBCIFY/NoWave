"""Turn pinned acquired snapshots into the real regional source catalogues.

Network access is opt-in. Heavy files stay outside Git. The regional preparer
remains local-only and retains responsibility for atomic generation publication.
"""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile
from xml.etree import ElementTree as ET

from pipeline_io import atomic_json, digest, feature, geometry_file

ROOT = Path(__file__).resolve().parents[1]
OSM_LICENSE = 'ODbL-1.0'
SHOM_LICENSE = 'Licence Ouverte 1.0 / Etalab, octobre 2011'
SHOM_SOURCE = ('Shom, 2015. MNT Golfe du Lion–Côte d’Azur (HOMONIM), '
               'https://doi.org/10.17183/MNT_MED100m_GDL_CA_HOMONIM_WGS84')


def asset(path, source, license_, date, **extra):
    return dict(path=str(path.resolve()), sha256=digest(path), source=source,
                license=license_, date=date, size_bytes=path.stat().st_size, **extra)


def command(osmium, *arguments):
    subprocess.run([osmium, *map(str, arguments)], check=True)


def complete_render_input(source, output, osmium):
    """Reject broken renderable relations; audit and omit unsupported references.

    Geofabrik keeps ways complete but not every route/administrative relation.
    Removing those unused relations recursively produces a fully checkable PBF;
    no way, node, or renderable multipolygon is truncated or approximated.
    """
    import osmium as pyosmium
    from shapely.geometry import box
    from regional_osm import normalize
    excluded = []
    working = source
    with tempfile.TemporaryDirectory(prefix='references-', dir=output.parent) as temp:
        for step in range(20):
            check = subprocess.run([osmium, 'check-refs', '-r', '-i', str(working)],
                                   capture_output=True, text=True)
            report = check.stdout + check.stderr
            if check.returncode == 0:
                command(osmium, 'cat', working, '-o', output, '--overwrite')
                return {'complete': True, 'check': report.strip(), 'excluded_relations': excluded}
            if re.search(r'[nwr]\d+ in w\d+', report):
                raise ValueError('Source has incomplete ways; acquire their actual references')
            ids = {int(i) for i in re.findall(r'[nwr]\d+ in r(\d+)', report)}
            if not ids:
                raise ValueError('Reference check failed: ' + report)
            removed = []
            for obj in pyosmium.FileProcessor(str(working)).with_filter(
                    pyosmium.filter.EntityFilter(pyosmium.osm.RELATION)):
                if obj.id not in ids:
                    continue
                tags = dict(obj.tags)
                if normalize(tags, box(0, 0, 1, 1)):
                    raise ValueError(f'Renderable relation/{obj.id} is incomplete; acquire references')
                removed.append('r' + str(obj.id))
                excluded.append({'osm_id': 'relation/' + str(obj.id), 'osm_tags': tags,
                    'reason': 'Incomplete producer relation, no supported rendering mapping'})
            if not removed:
                raise ValueError('Reference repair made no progress')
            id_file = Path(temp) / 'remove.txt'
            id_file.write_text('\n'.join(removed) + '\n')
            next_file = Path(temp) / f'{step}.osm.pbf'
            command(osmium, 'removeid', working, '--id-file', id_file, '-o', next_file)
            working = next_file
    raise ValueError('Reference dependency depth exceeded; nothing published')


def assembled_land(archive, output, bbox):
    import shapefile
    from shapely import make_valid
    from shapely.geometry import box, shape
    from shapely.ops import unary_union
    with tempfile.TemporaryDirectory(prefix='land-', dir=output.parent) as temp:
        with zipfile.ZipFile(archive) as package:
            # Only the producer's known shapefile components; no untrusted paths.
            for suffix in ('shp', 'shx', 'dbf', 'prj', 'cpg', 'txt'):
                name = ('land-polygons-split-4326/README.txt' if suffix == 'txt' else
                        'land-polygons-split-4326/land_polygons.' + suffix)
                target = Path(temp) / Path(name).name
                with package.open(name) as src, target.open('wb') as dst:
                    import shutil
                    shutil.copyfileobj(src, dst)
        extent = box(*bbox)
        with shapefile.Reader(Path(temp) / 'land_polygons.shp') as reader:
            parts = [make_valid(shape(s.__geo_interface__)).intersection(extent)
                     for s in reader.iterShapes(bbox=bbox)]
        land = unary_union(parts)
        atomic_json(output, feature('land', land, source='OSM assembled coastline / osmdata.openstreetmap.de',
                                    license=OSM_LICENSE, clip_bbox=bbox))


def french_scope(merged, output, relations, osmium):
    import osmium as pyosmium
    from shapely.geometry import shape
    from shapely.ops import unary_union
    factory = pyosmium.geom.GeoJSONFactory()
    found, parts = {}, []
    with tempfile.TemporaryDirectory(prefix='scope-', dir=output.parent) as temp:
        pbf = Path(temp) / 'departments.osm.pbf'
        command(osmium, 'getid', merged, *['r' + str(i) for i in relations.values()],
                '--add-referenced', '-o', pbf)
        # Administrative nesting outside these seven departments need not be read.
        processor = pyosmium.FileProcessor(str(pbf)).with_locations(
            'sparse_file_array,' + str(Path(temp) / 'locations.idx')).with_areas()
        for obj in processor:
            if not obj.is_area() or obj.from_way() or obj.orig_id() not in relations.values():
                continue
            tags = dict(obj.tags)
            code = tags.get('ref:INSEE')
            geom = shape(json.loads(factory.create_multipolygon(obj)))
            if code not in relations or not geom.is_valid:
                raise ValueError('Invalid department boundary for coast selection')
            found[code] = dict(osm_id='relation/' + str(obj.orig_id()),
                               osm_version=obj.version, osm_tags=tags)
            parts.append(geom)
    if set(found) != set(relations):
        raise ValueError('Missing department geometry; never substitute a bbox for scope')
    atomic_json(output, feature('coast_scope', unary_union(parts), source='OSM administrative departments',
        license=OSM_LICENSE, departments=found, selection_only=True,
        warning='Selection of real coastline only; not an official maritime boundary'))


def homonim(archive, root):
    import py7zr
    import numpy as np
    import rasterio
    from rasterio.features import shapes
    from shapely.geometry import shape
    from shapely.ops import unary_union
    directory = root / 'homonim-original'
    asc_name = ('MNT_FACADE_GDL-CA_HOMONIM_PBMA/DONNEES/'
                'MNT_MED100m_GDL-CA_HOMONIM_WGS84_PBMA_ZNEG.asc')
    xml_name = 'MNT_FACADE_GDL-CA_HOMONIM_PBMA/MNT_MED100m_GDL_CA_HOMONIM_WGS84_PBMA_ZNEG.xml'
    with py7zr.SevenZipFile(archive) as package:
        package.extract(path=directory, targets=[asc_name, xml_name,
            'MNT_FACADE_GDL-CA_HOMONIM_PBMA/Descriptif_Contenu_MNT_facade_2015.pdf'])
    asc, metadata = directory / asc_name, directory / xml_name
    xml = metadata.read_text()
    if not all(text in xml for text in ('WGS84', 'Plus Basse Mer Astronomique', 'Licence Ouverte')):
        raise ValueError('HOMONIM reference/license not confirmed by acquired XML')
    raster, coverage = root / 'homonim-pbma.tif', root / 'homonim-valid-coverage.geojson'
    temporary = raster.with_suffix('.tmp.tif')
    with rasterio.open(asc) as src:
        if src.nodata != -99999 or abs(src.res[0] - .001) > 1e-10:
            raise ValueError('Unexpected HOMONIM NoData/resolution')
        values = src.read(1, masked=True)
        with rasterio.open(temporary, 'w', driver='GTiff', width=src.width, height=src.height,
                count=1, dtype='float32', crs='EPSG:4326', transform=src.transform,
                nodata=src.nodata, tiled=True, compress='deflate') as dst:
            # Assign the CRS specified by XML; preserve grid, elevations and NoData.
            dst.write(values.filled(src.nodata).astype('float32'), 1)
        valid = ~np.ma.getmaskarray(values) & np.isfinite(values.data) & (values.data <= 0)
        footprint = unary_union([shape(g) for g, _ in shapes(valid.astype('uint8'), mask=valid,
                                                            transform=src.transform)])
    os.replace(temporary, raster)
    atomic_json(coverage, feature('bathymetry_coverage', footprint,
        source='Valid nonpositive original HOMONIM PBMA ZNEG cells', license=SHOM_LICENSE,
        positive='up', nodata=-99999, original_grid_sha256=digest(asc)))
    return dict(id='MNT_MED100m_GDL_CA_HOMONIM_WGS84_PBMA_ZNEG',
        **asset(raster, SHOM_SOURCE, SHOM_LICENSE, '2015'), resolution_m=111,
        resolution_degrees=.001, vertical_reference='PBMA', positive='up', priority=0,
        coverage=asset(coverage, 'Footprint of actual valid original cells', SHOM_LICENSE, '2015'),
        metadata=asset(metadata, 'Original SHOM product XML from acquired archive', SHOM_LICENSE, '2015'),
        original_grid=asset(asc, SHOM_SOURCE, SHOM_LICENSE, '2015'),
        archive_sha256=digest(archive),
        conversion='AAIGrid ZNEG to float32 GeoTIFF, CRS assigned from original WGS84 XML; no resampling',
        limitations='Regional model ~111 m, includes producer interpolation/global inputs; not a port survey')


def prepare(root, lock_path, osmium, download=False):
    import osmium as pyosmium
    from fetch_source import fetch
    lock = json.loads(lock_path.read_text())
    root.mkdir(parents=True, exist_ok=True)
    if sum(a['size_bytes'] for a in lock['assets']) > 2 * 1024**3:
        raise ValueError('Acquisition exceeds the explicit 2 GiB budget')
    for entry in lock['assets']:
        path = root / entry['name']
        if download:
            fetch(entry['url'], path, entry['sha256'], entry['size_bytes'], 2 * 1024**3)
        if path.stat().st_size != entry['size_bytes'] or digest(path) != entry['sha256']:
            raise ValueError('Acquired snapshot differs from pinned source: ' + entry['name'])
    inputs = [root / a['name'] for a in lock['assets'] if a['name'].endswith('.osm.pbf')]
    for path in inputs:
        with closing(pyosmium.io.Reader(str(path))) as reader:
            if reader.header().get('osmosis_replication_timestamp') != lock['osm_timestamp']:
                raise ValueError('Regional PBF snapshots must have the same timestamp')
    supplements = []
    for entry in lock['assets']:
        if entry.get('role') != 'osm_references':
            continue
        xml = root / entry['name']
        for obj in ET.parse(xml).getroot():
            if obj.tag in ('node', 'way', 'relation') and (
                    not obj.get('timestamp') or obj.get('timestamp') > lock['osm_timestamp']):
                raise ValueError('OSM reference supplement is newer than the pinned snapshot')
        pbf = xml.with_suffix('.osm.pbf')
        command(osmium, 'sort', xml, '-o', pbf, '--overwrite')
        supplements.append(pbf)
    merged, filtered = root / 'france-med-261003.osm.pbf', root / 'france-med-nautical-filtered.osm.pbf'
    command(osmium, 'merge', *inputs, *supplements, '-o', merged, '--overwrite',
            '--output-header=osmosis_replication_timestamp=' + lock['osm_timestamp'])
    command(osmium, 'tags-filter', merged, 'nwr/natural', 'nwr/landuse', 'nwr/leisure',
        'nwr/harbour', 'nwr/waterway', 'nwr/man_made', 'nwr/place',
        'nwr/highway=motorway,trunk,primary', 'nwr/seamark:type', '-o', filtered, '--overwrite')
    complete = root / 'france-med-render-complete-261003.osm.pbf'
    reference_audit = complete_render_input(filtered, complete, osmium)
    audit = root / 'osm-reference-audit.json'
    atomic_json(audit, reference_audit)
    land, scope = root / 'land-france-med.geojson', root / 'french-mainland-coast-scope.geojson'
    land_entry = next(a for a in lock['assets'] if a['name'].endswith('.zip'))
    assembled_land(root / land_entry['name'], land, lock['land_clip_bbox'])
    french_scope(merged, scope, lock['department_relations'], osmium)
    geometry_file(land)
    geometry_file(scope)
    shom_entry = next(a for a in lock['assets'] if a['name'].endswith('.7z'))
    product = homonim(root / shom_entry['name'], root)
    sources = dict(schema=1,
        osm=asset(complete, 'OpenStreetMap / Geofabrik regional snapshots, merge + reference-complete nautical filter',
                  OSM_LICENSE, lock['osm_timestamp'], acquisition=lock,
                  reference_audit=asset(audit, 'OSM producer-reference audit', OSM_LICENSE, lock['osm_timestamp'])),
        land=asset(land, 'OSM assembled coast / https://osmdata.openstreetmap.de/data/land-polygons.html',
                   OSM_LICENSE, land_entry['date'], archive_sha256=land_entry['sha256']),
        coast_scope=asset(scope, 'Seven OSM administrative departments from same snapshot; coast selection only',
                          OSM_LICENSE, lock['osm_timestamp']))
    atomic_json(ROOT / 'regions/france_med.sources.local.json', sources)
    atomic_json(ROOT / 'regions/france_med.bathymetry.local.json',
                dict(schema=1, vertical_reference='PBMA', products=[product]))
    print(json.dumps({'sources': str(ROOT / 'regions/france_med.sources.local.json'),
                      'bathymetry': str(ROOT / 'regions/france_med.bathymetry.local.json'),
                      'references': reference_audit['check']}, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path,
                        default=Path.home() / '.local/share/nowave/sources')
    parser.add_argument('--lock', type=Path, default=ROOT / 'regions/france_med.acquisition.json')
    parser.add_argument('--osmium', default='osmium')
    parser.add_argument('--download', action='store_true', help='Opt in to SHA256-pinned downloads, <=2 GiB total')
    args = parser.parse_args()
    prepare(args.source_root.resolve(), args.lock, args.osmium, args.download)


if __name__ == '__main__':
    main()
