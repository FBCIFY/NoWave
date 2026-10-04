"""Offline geographic, numerical and end-to-end regional pipeline regressions."""
import argparse
from contextlib import closing
from collections import Counter
import copy
import gzip
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen
from unittest.mock import patch

import contourpy
import numpy as np
import osmium
from PIL import Image
import rasterio
from rasterio.transform import from_origin
from shapely.geometry import box, LineString, Point, mapping
from shapely.ops import transform, unary_union

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_style import build_cassis, build_real_area, region_profile, COLORS
from build_bathymetry_tiles import build_region_tiles
from coastal_geometry import coastal_zone, TO_METRIC, TO_WGS84
from pipeline_io import atomic_json, digest, feature, current_generation
from fetch_source import fetch
from prepare_cassis import overpass_bbox
from prepare_region import prepare
from region_config import load_region, resolve_region
from regional_bathymetry import build_field, contours, load_catalog, rgba_from_depth
from regional_osm import normalize, ingest, extract_pbf

spec = importlib.util.spec_from_file_location('regional_server', ROOT / 'server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


def asset(path, source='OFFLINE TEST FIXTURE'):
    return {'path': str(path), 'sha256': digest(path), 'source': source,
            'license': 'test fixture only', 'date': '2026-01-01'}


def fixture(directory):
    """Explicitly synthetic numerical fixture; never published as SHOM coverage."""
    x, y = TO_METRIC(5.535, 43.21)
    x, y = round(x / 100) * 100, round(y / 100) * 100
    extent = box(x - 1600, y - 1600, x + 1600, y + 1600)
    land = box(x - 1700, y, x + 1700, y + 1700)
    coast = LineString([(x - 1700, y), (x + 1700, y)])
    bbox = list(transform(TO_WGS84, extent).bounds)
    region = {'schema': 1, 'id': 'fixture', 'name': 'OFFLINE FIXTURE', 'bbox': bbox,
              'center': [5.535, 43.21], 'zoom': 12,
              'coverage': {'sea_buffer_nm': 10}, 'sources': {'vector': 'OSM', 'bathymetry': 'FIXTURE', 'relief': 'Mapzen'}}
    for name, geom in [('land', land), ('scope', extent), ('coverage', extent), ('sea', extent.difference(land))]:
        atomic_json(directory / (name + '.geojson'), feature(name, transform(TO_WGS84, geom)))
    (directory / 'metadata.xml').write_text('<test>NOT REAL SHOM DATA</test>')
    products = []
    for name, resolution in [('fine', 10), ('coarse', 100)]:
        values = np.tile(np.arange(32, dtype='float32') + 1, (32, 1))
        if name == 'fine':
            values[:] = 7
            values[:, 16:] = -9999
        values[:, :3] = -9999  # NoData in both products must remain unknown.
        path = directory / (name + '.tif')
        with rasterio.open(path, 'w', driver='GTiff', width=32, height=32, count=1, dtype='float32',
                           crs='EPSG:2154', transform=from_origin(x-1600, y+1600, 100, 100), nodata=-9999) as dst:
            dst.write(values, 1)
        products.append({**asset(path), 'id': name, 'resolution_m': resolution, 'positive': 'down',
                         'vertical_reference': 'TEST_DATUM', 'coverage': asset(directory / 'coverage.geojson'),
                         'metadata': asset(directory / 'metadata.xml')})
    catalog = directory / 'catalog.json'
    atomic_json(catalog, {'schema': 1, 'vertical_reference': 'TEST_DATUM', 'products': products})
    pbf = directory / 'input.osm.pbf'
    with osmium.SimpleWriter(str(pbf)) as writer:
        points = list(transform(TO_WGS84, coast).coords)
        for id_, (lon, lat) in enumerate(points, 1):
            writer.add_node(osmium.osm.mutable.Node(id=id_, location=(lon, lat), version=1))
        writer.add_node(osmium.osm.mutable.Node(id=3, location=TO_WGS84(x, y-100),
                        tags={'seamark:type': 'buoy_cardinal', 'seamark:buoy_cardinal:category': 'north'}, version=1))
        writer.add_node(osmium.osm.mutable.Node(id=4, location=TO_WGS84(x, y-200),
                        tags={'seamark:type': 'not_a_known_type'}, version=1))
        # Closed marina way, represented by area callback only.
        ring = [(x+200,y-200),(x+500,y-200),(x+500,y-500),(x+200,y-500)]
        for id_, xy in enumerate(ring, 5):
            writer.add_node(osmium.osm.mutable.Node(id=id_, location=TO_WGS84(*xy), version=1))
        writer.add_way(osmium.osm.mutable.Way(id=1, nodes=[1,2], tags={'natural':'coastline'}, version=1))
        writer.add_way(osmium.osm.mutable.Way(id=2, nodes=[5,6,7,8,5], tags={'leisure':'marina'}, version=1))
    sources = directory / 'sources.json'
    atomic_json(sources, {'schema': 1, 'osm': asset(pbf), 'land': asset(directory / 'land.geojson'),
                         'coast_scope': asset(directory / 'scope.geojson')})
    return region, catalog, sources


class RegionTest(unittest.TestCase):
    def test_region_configs_and_invalid_values(self):
        for name in ('cassis', 'france_med'):
            region = resolve_region(name)
            self.assertEqual(region['id'], name)
            self.assertFalse(region['coverage']['corsica'])
        self.assertEqual(resolve_region('france_med')['bbox'], [2.95,42.2,7.75,44.1])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.json'
            for key, bad in [('id','../bad'),('id','BAD'),('bbox',[5,43,4,44]),('bbox',[0,-90,2,90]),
                             ('center',[0,0]),('zoom',float('nan')),('coverage',{'sea_buffer_nm':float('inf')})]:
                region = copy.deepcopy(resolve_region('cassis'))
                region[key] = bad
                path.write_text(json.dumps(region))
                with self.assertRaises(ValueError, msg=str((key,bad))):
                    load_region(path)

    def test_metric_coastal_buffer_never_uses_bbox_edges(self):
        x,y = TO_METRIC(5.5,43.2)
        coast = transform(TO_WGS84, LineString([(x-1000,y),(x+1000,y)]))
        land = transform(TO_WGS84, box(x-50000,y,x+50000,y+50000))
        bounds = transform(TO_WGS84,box(x-50000,y-50000,x+50000,y+50000)).bounds
        sea, useful = coastal_zone(coast,land,bounds)
        metric = transform(TO_METRIC,sea)
        self.assertTrue(metric.contains(Point(x,y-18500)))
        self.assertFalse(metric.contains(Point(x,y-18600)))
        self.assertFalse(metric.contains(Point(x+45000,y-100)))
        self.assertFalse(metric.contains(Point(x,y+100)))
        self.assertTrue(useful.contains(Point(*TO_WGS84(x,y+100))))

    def test_cassis_exact_snapshot_and_overpass(self):
        baseline = json.loads((ROOT/'tests/fixtures/cassis-baseline.json').read_text())
        self.assertEqual(build_cassis(),baseline['style'])
        self.assertEqual([list(c) for c in COLORS],baseline['palette'])
        for path,sha in baseline['sha256'].items():
            self.assertEqual(digest(ROOT/path),sha,path)
        kinds = Counter(f['properties']['kind'] for f in json.loads((ROOT/'data/cassis/features.geojson').read_text())['features'])
        self.assertEqual(dict(kinds), baseline['kinds'])
        manifest = json.loads((ROOT/'data/cassis/manifest.json').read_text())
        self.assertEqual({k:manifest[k] for k in baseline['manifest']},baseline['manifest'])
        np.testing.assert_allclose(overpass_bbox(),[43.18,5.5,43.225,5.565])

    def test_pbf_relation_holes_and_cached_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            pbf = directory/'relations.osm.pbf'
            points = [(5.50,43.20),(5.54,43.20),(5.54,43.24),(5.50,43.24),
                      (5.51,43.21),(5.53,43.21),(5.53,43.23),(5.51,43.23)]
            with osmium.SimpleWriter(str(pbf)) as writer:
                for i,point in enumerate(points,1):
                    writer.add_node(osmium.osm.mutable.Node(id=i,location=point,version=1))
                writer.add_way(osmium.osm.mutable.Way(id=1,nodes=[1,2,3,4,1],version=1))
                writer.add_way(osmium.osm.mutable.Way(id=2,nodes=[5,6,7,8,5],version=1))
                writer.add_relation(osmium.osm.mutable.Relation(id=99,version=1,
                    tags={'type':'multipolygon','leisure':'marina'},members=[('w',1,'outer'),('w',2,'inner')]))
            # No original vertex lies in the bbox: area intersection must select the relation.
            bbox=[5.505,43.205,5.535,43.235]
            extracted=extract_pbf(pbf,bbox,directory)
            timestamp=extracted.stat().st_mtime_ns
            self.assertEqual(extract_pbf(pbf,bbox,directory).stat().st_mtime_ns,timestamp)
            db=ingest(extracted,directory/'inventory.sqlite',bbox,{},directory)
            try:
                records=[json.loads(row[0]) for row in db.execute('SELECT payload FROM features')]
                self.assertEqual(len(records),2)
                from shapely.geometry import shape
                marina=shape(next(f['geometry'] for f in records if f['properties']['kind']=='marina_extent'))
                self.assertFalse(marina.contains(Point(5.52,43.22)))
                self.assertTrue(marina.contains(Point(5.507,43.207)))
                self.assertTrue(all(f['properties']['osm_id']=='relation/99' for f in records))
            finally:
                db.close()

    def test_no_guess_for_unknown_objects(self):
        for tags in [{'seamark:type':'unknown'}, {'seamark:type':'buoy_cardinal'},
                     {'seamark:type':'buoy_lateral','seamark:buoy_lateral:category':'port'},
                     {'seamark:type':'harbour'}, {'seamark:type':'light_minor'}]:
            self.assertEqual(normalize(tags,Point(5,43)),[])

    def test_end_to_end_blocks_nodata_resume_provenance_style_mvt(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            region,catalog,sources = fixture(directory)
            output,cache = directory/'data',directory/'cache'
            manifest = prepare(region,sources,catalog,output,cache,resolution=100,block_size=16)
            output = current_generation(output)
            field = manifest['bathymetry']
            self.assertGreater(len(field['blocks']),1)
            with rasterio.open(field['depth_vrt']) as src:
                depth,source = src.read()
                self.assertTrue(np.all(np.isnan(depth[(source==0) | ~np.isfinite(source)])))
                self.assertTrue(np.all(depth[source==1]==7))
                self.assertTrue(np.any(source==2))
                self.assertTrue(np.isnan(depth).any())
            times = {b['file']:(Path(field['depth_vrt']).parent/b['file']).stat().st_mtime_ns for b in field['blocks']}
            repeated = build_field(catalog,output/'coverage.geojson',cache/'bathymetry',100,16)
            self.assertEqual(field,repeated)
            self.assertEqual(times,{b['file']:(Path(field['depth_vrt']).parent/b['file']).stat().st_mtime_ns for b in field['blocks']})
            # Deliberately corrupt a cached block: hash verification rebuilds it.
            damaged = Path(field['depth_vrt']).parent/field['blocks'][0]['file']
            damaged.write_bytes(b'incomplete')
            repaired = build_field(catalog,output/'coverage.geojson',cache/'bathymetry',100,16)
            self.assertEqual(repaired,field)
            contour_features = list(contours(field))
            self.assertTrue(contour_features)
            self.assertTrue(all(f['properties']['product_id']=='coarse' for f in contour_features))
            # Block contour union must equal one reference contour on the assembled field.
            from shapely.geometry import shape
            with rasterio.open(field['depth_vrt']) as src:
                d, source_ids = src.read()
                xs = src.transform.c + (np.arange(src.width) + .5) * src.transform.a
                ys = src.transform.f + (np.arange(src.height) + .5) * src.transform.e
                gen = contourpy.contour_generator(x=xs,y=ys,
                    z=np.ma.masked_where((source_ids != 2) | ~np.isfinite(d),d),corner_mask=False)
                reference = unary_union([LineString(c) for c in gen.lines(20)])
                tiled = unary_union([transform(TO_METRIC,shape(f['geometry'])) for f in contour_features
                                     if f['properties']['depth_m']==20])
                self.assertFalse(reference.is_empty)
                self.assertLess(reference.hausdorff_distance(tiled), 0.0001)
            values = json.loads((output/'features.geojson').read_text())['features']
            keys = [(f['properties'].get('osm_id'),f['properties']['kind']) for f in values if 'osm_id' in f['properties']]
            self.assertEqual(len(keys),len(set(keys)))
            self.assertEqual(sum(kind=='port' for _,kind in keys),1)
            self.assertEqual(sum(kind=='marina_extent' for _,kind in keys),1)
            skipped = json.loads((output/'osm-not-rendered.geojson').read_text())['features']
            self.assertEqual(skipped[0]['properties']['osm_id'],'node/4')
            tiles = directory/'tiles'
            metadata = build_region_tiles(output/'bathymetry.json',region['bbox'],tiles,10,11)
            pngs = list(tiles.glob('*/*/*.png'))
            self.assertTrue(pngs)
            arrays = [np.array(Image.open(p)) for p in pngs]
            self.assertTrue(all(a.shape==(256,256,4) for a in arrays))
            self.assertTrue(any((a[:,:,3]==0).any() for a in arrays))
            self.assertTrue(any((a[:,:,3]>0).any() for a in arrays))
            saved_times = {p:p.stat().st_mtime_ns for p in pngs}
            again = build_region_tiles(output/'bathymetry.json',region['bbox'],tiles,10,11)
            self.assertEqual(metadata,again)
            self.assertEqual(saved_times,{p:p.stat().st_mtime_ns for p in pngs})
            with self.assertRaisesRegex(ValueError,'justified limit'):
                build_region_tiles(output/'bathymetry.json',region['bbox'],tiles,10,18)
            for a in arrays:
                self.assertTrue(np.all(a[:,:,:3][a[:,:,3]>0] > 0))
            # Render with production France region camera but fixture-provenance manifest.
            france = resolve_region('france_med')
            styled_manifest = {**manifest,'region':'france_med','bbox':france['bbox']}
            style = build_real_area(region_profile('france_med',styled_manifest,metadata))
            self.assertTrue(all(l['source-layer']=='nowave' for l in style['layers'] if l.get('source')=='features'))
            self.assertEqual(style['sources']['bathymetry']['type'],'raster')
            self.assertIn('/france_med/',style['sources']['features']['tiles'][0])
            style_path = directory/'style.json'
            style_path.write_text(json.dumps(style))
            subprocess.run(['node','-e', "const fs=require('fs'); const v=require('@maplibre/maplibre-gl-style-spec').validateStyleMin; const e=v(JSON.parse(fs.readFileSync(process.argv[1]))); if(e.length){console.error(e);process.exit(1)}",str(style_path)],cwd=ROOT,check=True)
            mbtiles=directory/'fixture.mbtiles'
            import os
            subprocess.run([str(ROOT/'tools/build_vector_tiles.sh'),str(output/'features.geojson'),str(mbtiles),'nowave','regional'],
                           env={**os.environ,'MAX_ZOOM':'11'},check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            server.validate_mbtiles(mbtiles)
            with closing(sqlite3.connect(mbtiles)) as db:
                z,x,tms,payload=db.execute('SELECT zoom_level,tile_column,tile_row,tile_data FROM tiles LIMIT 1').fetchone()
                self.assertEqual(server.read_tile(mbtiles,z,x,2**z-1-tms),payload)
                self.assertTrue(gzip.decompress(payload))
            # Exercise the actual disk-backed regional style path and stale-output guard.
            import shutil
            import build_style
            published = directory/'published'
            (published/'data/france_med').mkdir(parents=True)
            (published/'tiles/vector').mkdir(parents=True)
            (published/'tiles/bathymetry/france_med').mkdir(parents=True)
            shutil.copyfile(mbtiles,published/'tiles/vector/france_med.mbtiles')
            atomic_json(published/'data/france_med/manifest.json',styled_manifest)
            atomic_json(published/'tiles/bathymetry/france_med/metadata.json',metadata)
            with patch.object(build_style,'ROOT',published):
                disk_style=build_style.build_region('france_med')
                self.assertEqual(disk_style['sources']['features']['maxzoom'],11)
                styled_manifest['features_sha256']='stale'
                atomic_json(published/'data/france_med/manifest.json',styled_manifest)
                with self.assertRaisesRegex(ValueError,'does not match prepared features'):
                    build_style.build_region('france_med')

    def test_vertical_mismatch_checksum_and_no_zero_fill(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)
            _,catalog,_=fixture(directory)
            data=json.loads(catalog.read_text())
            data['products'][1]['vertical_reference']='OTHER'
            atomic_json(catalog,data)
            with self.assertRaisesRegex(ValueError,'Mixed vertical'):
                load_catalog(catalog)
            data['products'][1]['vertical_reference']='TEST_DATUM'
            data['products'][0]['sha256']='bad'
            atomic_json(catalog,data)
            with self.assertRaisesRegex(ValueError,'SHA256'):
                load_catalog(catalog)
            rgba=rgba_from_depth(np.array([[np.nan,0,5]],dtype='float32'))
            self.assertEqual(rgba[3,0].tolist(),[0,255,255])
            self.assertEqual(rgba[:3,0,1].tolist(),[244,251,255])

    def test_source_acquisition_budget_and_checksums_without_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)/'asset'
            target.write_bytes(b'verified source')
            checksum = digest(target)
            with patch('fetch_source.urlopen', side_effect=AssertionError('Network must not be used')):
                self.assertEqual(fetch('https://example.invalid/source',target,checksum,15,100),target)
                with self.assertRaisesRegex(ValueError,'budget'):
                    fetch('https://example.invalid/source',target,checksum,101,100)
                with self.assertRaisesRegex(ValueError,'SHA256'):
                    fetch('https://example.invalid/source',target,'unknown',15,100)

    def test_explicit_footprint_exclusion_and_signed_elevation(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            region,catalog,_ = fixture(directory)
            data=json.loads(catalog.read_text())
            data['products'][0]['positive']='up'  # positive elevation is land, not depth.
            data['products'][1]['exclude']=asset(directory/'sea.geojson')
            atomic_json(catalog,data)
            result=build_field(catalog,directory/'sea.geojson',directory/'field',100,16)
            self.assertEqual(result['valid_cells'],0)
            with rasterio.open(result['depth_vrt']) as src:
                self.assertTrue(np.isnan(src.read(1)).all())

    def test_regional_http_xyz_gzip_and_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            vector=root/'tiles/vector';vector.mkdir(parents=True)
            path=vector/'france_med.mbtiles'
            payload=gzip.compress(b'mvt-test')
            with closing(sqlite3.connect(path)) as db:
                db.execute('CREATE TABLE tiles (zoom_level,tile_column,tile_row,tile_data)')
                db.execute('INSERT INTO tiles VALUES (2,1,3,?)',(payload,))
                db.commit()
            config=argparse.Namespace(region='france_med',real_cassis=False,mbtiles=None,public_url=None,
                bathymetry_tiles=None,relief_tiles=None,attribution=None,center=None)
            with patch.object(server,'ROOT',root):
                httpd=ThreadingHTTPServer(('127.0.0.1',0),server.handler_class(config))
                thread=threading.Thread(target=httpd.serve_forever,daemon=True);thread.start()
                base=f'http://127.0.0.1:{httpd.server_port}'
                try:
                    with urlopen(base+'/tiles/vector/france_med/2/1/0.pbf') as response:
                        self.assertEqual(response.read(),payload)
                        self.assertEqual(response.headers['Content-Encoding'],'gzip')
                        self.assertEqual(response.headers['Content-Type'],'application/vnd.mapbox-vector-tile')
                        self.assertEqual(response.headers['Access-Control-Allow-Origin'],'*')
                    with urlopen(base+'/tiles/vector/france_med/2/1/1.pbf') as response:
                        self.assertEqual(response.status,204)
                    with urlopen(base+'/tiles/bathymetry/france_med/2/1/1.png') as response:
                        self.assertEqual(response.status,204)
                    for url in ['/tiles/vector/%2e%2e/2/1/0.pbf','/tiles/vector/cassis/2/1/0.pbf',
                                '/tiles/bathymetry/%2e%2e/server.py','/data/%2e%2e/server.py']:
                        with self.assertRaises(HTTPError) as error:
                            urlopen(base+url)
                        self.assertEqual(error.exception.code,404)
                        error.exception.close()
                finally:
                    httpd.shutdown();httpd.server_close();thread.join()


if __name__=='__main__':
    unittest.main()
