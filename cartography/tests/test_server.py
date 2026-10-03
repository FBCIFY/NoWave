import argparse
import gzip
import importlib.util
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen
from http.server import ThreadingHTTPServer

spec = importlib.util.spec_from_file_location('map_server', Path(__file__).resolve().parents[1]/'server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class MapServerTest(unittest.TestCase):
    def test_real_mode_has_no_demo_sources_and_requires_provenance(self):
        with self.assertRaises(ValueError):
            server.make_style('http://test', 'map.mbtiles')
        style = server.make_style('http://test', 'map.mbtiles',
                                  'http://test/bathy/{z}/{x}/{y}.png', attribution='Source réelle')
        serialized = json.dumps(style)
        self.assertNotIn('demo', serialized.lower())
        self.assertEqual(style['sources']['features']['type'], 'vector')
        self.assertTrue(all(l['source-layer'] == 'nowave' for l in style['layers']
                            if l.get('source') == 'features'))
        self.assertNotIn('land-relief', [l['id'] for l in style['layers']])

    def test_xyz_to_tms_and_gzip_tile_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'test.mbtiles'
            payload = gzip.compress(b'vector-tile-test-payload')
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE tiles (zoom_level, tile_column, tile_row, tile_data)')
                db.execute('INSERT INTO tiles VALUES (2, 1, 3, ?)', (payload,))
            config = argparse.Namespace(mbtiles=path, public_url=None, bathymetry_tiles='http://test/b/{z}/{x}/{y}',
                                        relief_tiles=None, attribution='Source', center=None)
            httpd = ThreadingHTTPServer(('127.0.0.1', 0), server.handler_class(config))
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            try:
                base = f'http://127.0.0.1:{httpd.server_port}'
                with urlopen(base+'/tiles/2/1/0.pbf') as response:
                    self.assertEqual(response.headers['Content-Encoding'], 'gzip')
                    self.assertEqual(response.headers['Access-Control-Allow-Origin'], '*')
                    self.assertEqual(response.read(), payload)
                with urlopen(base+'/tiles/2/1/1.pbf') as response:
                    self.assertEqual(response.status, 204)
                with self.assertRaises(HTTPError) as error:
                    urlopen(base+'/data/demo.geojson')
                self.assertEqual(error.exception.code, 404)
                error.exception.close()
                for target in ['/assets/../server.py', '/assets/../data/demo.geojson']:
                    with self.assertRaises(HTTPError) as error:
                        urlopen(base+target)
                    error.exception.close()
            finally:
                httpd.shutdown()
                httpd.server_close()
                thread.join()
            self.assertIsNone(server.read_tile(path, 2, 4, 0))

    def test_demo_features_and_icons_are_explicit(self):
        data = json.loads((server.ROOT/'data/demo.geojson').read_text())
        sprites = json.loads((server.ROOT/'assets/sprite.json').read_text())
        self.assertGreater(len(data['features']), 50)
        for feature in data['features']:
            properties = feature['properties']
            self.assertIs(properties['demo'], True)
            if 'icon' in properties:
                self.assertIn(properties['icon'], sprites)
        style = server.make_style('http://localhost:8765')
        self.assertEqual(style['metadata']['nowave:data_mode'], 'DEMO_FICTIVE')
        self.assertNotIn('{base}', json.dumps(style))


if __name__ == '__main__':
    unittest.main()
