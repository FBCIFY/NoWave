import importlib.util
import json
import sys
import unittest
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from build_style import build, MAPZEN_TILES
spec = importlib.util.spec_from_file_location('relief_server', ROOT/'server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class ReliefTest(unittest.TestCase):
    def test_real_dem_and_discreet_zoom_interpolation(self):
        style = build()
        source = style['sources']['relief']
        self.assertEqual(source['type'], 'raster-dem')
        self.assertEqual(source['encoding'], 'terrarium')
        self.assertEqual(source['tileSize'], 256)
        self.assertEqual(source['tiles'], [MAPZEN_TILES])
        relief = next(l for l in style['layers'] if l['id'] == 'land-relief')
        self.assertEqual(relief['type'], 'hillshade')
        self.assertEqual(relief['paint']['hillshade-exaggeration'],
                         ['interpolate', ['linear'], ['zoom'], 7, 0, 10, .15, 14, .2, 18, .22])
        self.assertIn('Terrain data credits', source['attribution'])
        self.assertNotIn('demo-relief.png', json.dumps(style))
        self.assertEqual(style['sources']['bathymetry']['url'], '{base}/assets/demo-bathymetry.png')

    def test_sea_mask_preserves_bathymetry_pixels_and_land_transparency(self):
        original = Image.open(ROOT/'assets/demo-bathymetry.png').convert('RGB')
        mask = Image.open(ROOT/'assets/demo-sea-mask.png').convert('RGBA')
        self.assertEqual(original.size, mask.size)
        self.assertIsNone(ImageChops.difference(original, mask.convert('RGB')).getbbox())
        width, height = mask.size
        self.assertEqual(mask.getpixel((0, 0))[3], 255)
        self.assertEqual(mask.getpixel((width//2, height//2))[3], 0)
        layers = [l['id'] for l in build()['layers']]
        self.assertLess(layers.index('land-relief'), layers.index('relief-sea-mask'))
        self.assertLess(layers.index('relief-sea-mask'), layers.index('contours'))

    def test_preview_and_camera_configuration_do_not_relocate_fictitious_features(self):
        demo = server.make_style('http://test', center=[5.5, 43.22], zoom=12)
        self.assertEqual(demo['center'], [5.5, 43.22])
        self.assertEqual(demo['sources']['features']['data'], 'http://test/data/demo.geojson')
        preview = server.make_style('http://test', relief_preview=True, center=[5.54, 43.21], zoom=13)
        self.assertEqual(preview['metadata']['nowave:data_mode'], 'RELIEF_REAL_PREVIEW')
        self.assertEqual(preview['center'], [5.54, 43.21])
        self.assertNotIn('features', preview['sources'])
        self.assertNotIn('bathymetry', preview['sources'])
        self.assertEqual(preview['sources']['relief'], demo['sources']['relief'])

    def test_dem_swap_changes_only_source_and_credits(self):
        original = server.make_style('http://test')
        with self.assertRaises(ValueError):
            server.make_style('http://test', relief='http://test/dem/{z}/{x}/{y}.png')
        custom = server.make_style('http://test', relief='http://test/dem/{z}/{x}/{y}.png',
                                   relief_attribution='Own DEM credits')
        self.assertEqual(original['layers'], custom['layers'])
        self.assertEqual(custom['sources']['relief']['encoding'], 'terrarium')
        self.assertEqual(custom['sources']['relief']['attribution'], 'Own DEM credits')


if __name__ == '__main__':
    unittest.main()
