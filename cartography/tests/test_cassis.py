"""Real-pilot integrity: provenance, water protection and measured support."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen

import numpy as np
from PIL import Image
from shapely.geometry import Point, shape

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from prepare_cassis import ClippedXYZ, BBOX
from build_style import build, build_cassis
spec = importlib.util.spec_from_file_location('cassis_server', ROOT/'server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class CassisTest(unittest.TestCase):
    def test_real_mode_preserves_dem_and_visual_rules_without_demo_inputs(self):
        style, demo = build_cassis(), build()
        self.assertEqual(style['metadata']['nowave:data_mode'], 'CASSIS_REAL')
        self.assertEqual(style['sources']['relief'], demo['sources']['relief'])
        self.assertNotIn('demo-', json.dumps(style))
        self.assertNotIn('demo.geojson', json.dumps(style))
        for id_ in ['land-relief', 'contours', 'coast', 'pontoons', 'port-symbols', 'light-symbols']:
            actual = next(l for l in style['layers'] if l['id'] == id_)
            expected = dict(next(l for l in demo['layers'] if l['id'] == id_))
            if expected.get('source') == 'features':
                expected['source-layer'] = 'nowave'
            self.assertEqual(actual, expected)
        layers = [l['id'] for l in style['layers']]
        self.assertLess(layers.index('land'), layers.index('land-relief'))
        self.assertLess(layers.index('land-relief'), layers.index('relief-sea-mask'))
        self.assertLess(layers.index('relief-sea-mask'), layers.index('bathymetry'))
        self.assertEqual(next(l for l in style['layers'] if l['id'] == 'relief-sea-mask')['type'], 'fill')

    def test_coastline_distinguishes_real_land_port_and_approach(self):
        features = json.loads((ROOT/'data/cassis/features.geojson').read_text())['features']
        land = shape(next(f['geometry'] for f in features if f['properties']['kind'] == 'land'))
        water = shape(json.loads((ROOT/'data/cassis/water.geojson').read_text())['geometry'])
        self.assertTrue(land.is_valid)
        self.assertTrue(water.is_valid)
        self.assertTrue(land.contains(Point(5.54, 43.217)))
        for point in [Point(5.536, 43.214), Point(5.535, 43.207)]:
            self.assertFalse(land.contains(point))
            self.assertTrue(water.contains(point))
        for f in features:
            p = f['properties']
            self.assertIs(p['demo'], False)
            self.assertTrue(p.get('source'))
            if 'osm_id' in p:
                self.assertTrue(p['osm_tags'])
                self.assertTrue(p['retrieved_at'])
                self.assertIn(p['osm_id'].split('/')[0], ['node', 'way', 'relation'])

    def test_missing_depth_is_transparent_and_port_has_no_regional_invention(self):
        from shapely import contains_xy
        field = np.load(ROOT/'data/cassis/depth-grid.npz')
        depth, source = field['depth_m'], field['source']
        alpha = np.asarray(Image.open(ROOT/'assets/cassis-bathymetry.png'))[:, :, 3]
        self.assertTrue(np.all(alpha[source == 0] == 0))
        self.assertTrue(np.all(alpha[source > 0] == 255))
        self.assertTrue(np.all(np.isnan(depth[source == 0])))
        self.assertTrue(np.all(depth[source > 0] >= 0))
        features = json.loads((ROOT/'data/cassis/features.geojson').read_text())['features']
        marina = shape(next(f['geometry'] for f in features if f['properties']['kind'] == 'marina_extent'))
        xx, yy = np.meshgrid(field['x'], field['y'])
        self.assertFalse(np.any(source[contains_xy(marina, xx, yy)] == 1))
        for f in features:
            if f['properties']['kind'] == 'contour':
                self.assertIn(f['properties']['source'], ['SHOM S201300200', 'SHOM HOMONIM'])
                if f['properties']['source'] == 'SHOM HOMONIM':
                    self.assertGreaterEqual(f['properties']['depth_m'], 10)

    def test_xyz_stream_retains_only_small_bbox_and_preserves_signed_depths(self):
        stream = ClippedXYZ()
        header = b'Bathymetry produced by Shom\r\nS201300200\r\nlong,lat,depth\r\n'
        data = header+b'5.536,43.214,3.5\r\n0,0,99\r\n5.535,43.213,-2\r\n'
        for size in [len(header)+5, 4, 10, 20, len(data)]:
            block, data = data[:size], data[size:]
            stream.write(block)
        stream.consume(stream.pending)
        result = np.concatenate(stream.chunks)
        self.assertEqual(stream.count, 3)
        self.assertEqual(result.shape, (2, 3))
        self.assertEqual(result[:, 2].tolist(), [3.5, -2])

    def test_http_real_mode_refuses_synthetic_assets(self):
        config = argparse.Namespace(real_cassis=True, mbtiles=None, public_url=None,
            bathymetry_tiles=None, relief_tiles=None, attribution=None, center=None)
        httpd = ThreadingHTTPServer(('127.0.0.1', 0), server.handler_class(config))
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            base = f'http://127.0.0.1:{httpd.server_port}'
            with urlopen(base+'/style.json') as response:
                style = json.load(response)
                self.assertEqual(style['metadata']['nowave:data_mode'], 'CASSIS_REAL')
            for path in ['/data/demo.geojson', '/assets/demo-bathymetry.png',
                         '/assets/mapzen-preview-sea-mask.png', '/data//demo.geojson']:
                with self.assertRaises(HTTPError) as error: urlopen(base+path)
                self.assertEqual(error.exception.code, 404)
                error.exception.close()
            with urlopen(base+'/data/cassis/features.geojson') as response:
                self.assertEqual(response.status, 200)
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join()
        with self.assertRaises(ValueError): server.make_style('http://test', real_cassis=True, relief_preview=True)


if __name__ == '__main__': unittest.main()
