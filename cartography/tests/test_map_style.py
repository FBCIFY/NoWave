"""Offline label boundaries, explicit IALA A mappings and atlas pixel regressions."""
from contextlib import closing
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import osmium
from PIL import Image
from shapely.geometry import Point

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_style import build, build_real_area, region_profile, COUNTRY_CITY_SWITCH_ZOOM
from generate_demo import sprites
from pipeline_io import current_generation, digest, iter_collection
from prepare_region import prepare
from regional_osm import normalize, ingest, SEAMARK_SCHEMES, SEAMARK_SHAPES
from region_config import resolve_region, load_region
from test_regions import fixture


def tags_for(family, category, shape='pillar', beacon=False, topmark=False):
    scheme = SEAMARK_SCHEMES[(family, category)]
    type_ = ('beacon_' if beacon else 'buoy_') + family
    prefix = 'seamark:' + type_ + ':'
    tags = {'seamark:type': type_, prefix + 'colour': scheme[1], prefix + 'shape': shape}
    if category is not None:
        tags[prefix + 'category'] = category
    if scheme[2]:
        tags[prefix + 'colour_pattern'] = scheme[2]
    if topmark:
        tags.update({'seamark:topmark:shape': scheme[3], 'seamark:topmark:colour': scheme[4]})
    return tags


class LabelsTest(unittest.TestCase):
    def test_country_city_boundary_and_other_labels(self):
        manifest = json.loads((ROOT / 'tests/fixtures/france-med-manifest.json').read_text())
        style = build_real_area(region_profile('france_med', manifest,
                                {'minzoom': 6, 'maxzoom': 11, 'field_signature': 'fixture-only'}))
        layers = {l['id']: l for l in style['layers']}
        country, city = layers['country'], layers['coastal_city']
        self.assertEqual(country['maxzoom'], COUNTRY_CITY_SWITCH_ZOOM)
        self.assertGreater(city['minzoom'], 6)
        self.assertEqual(city['minzoom'], country['maxzoom'])
        self.assertEqual(city['maxzoom'], 12)
        self.assertEqual(country['paint']['text-opacity'], 1)
        self.assertEqual(city['paint']['text-opacity'], 1)
        for zoom, expected in [(4, (True, False)), (6, (True, False)),
                               (COUNTRY_CITY_SWITCH_ZOOM - .0001, (True, False)),
                               (COUNTRY_CITY_SWITCH_ZOOM, (False, True)),
                               (7, (False, True)), (11.9999, (False, True)),
                               (12, (False, False)), (15, (False, False))]:
            visible = tuple(l['minzoom'] <= zoom < l['maxzoom'] for l in (country, city))
            self.assertEqual(visible, expected, zoom)
        self.assertEqual(country['source'], 'country')
        self.assertNotIn('source-layer', country)
        data = style['sources']['country']['data']
        self.assertEqual(data['properties'], {'kind': 'country', 'name': 'FRANCE'})
        self.assertEqual(data['geometry']['coordinates'], [4.8, 44.1])
        self.assertFalse(resolve_region('france_med')['coverage']['corsica'])
        # Compare every pre-existing geographic label with the retained Cassis snapshot.
        baseline = json.loads((ROOT / 'tests/fixtures/cassis-baseline.json').read_text())['style']
        for layer in baseline['layers']:
            if layer['id'] in ('sea_name', 'gulf_name', 'roadstead_name', 'coastal_town',
                               'bay_name', 'cape_name', 'island_name', 'beach_name', 'cove_name', 'calanque_name'):
                self.assertEqual(layers[layer['id']], layer)
        self.assertNotIn('maxzoom', layers['coastal_town'])
        self.assertEqual(layers['coastal_town']['minzoom'], 12)
        self.assertEqual(next(l for l in build()['layers'] if l['id'] == 'coastal_city')['maxzoom'], 12)

    def test_country_config_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'region.json'
            for country in ({'name': ''}, {'name': 'FRANCE', 'coordinates': [0, 0]},
                            {'name': 'FRANCE', 'coordinates': [float('nan'), 44]},
                            {'name': 'FRANCE', 'coordinates': [4.8]}):
                config = resolve_region('france_med')
                config['country_label'] = country
                path.write_text(json.dumps(config))
                with self.assertRaises(ValueError):
                    load_region(path)


class SeamarksTest(unittest.TestCase):
    def test_osm_categories_have_independent_iala_a_expectations(self):
        # Literal OSM inputs/outputs: a reversed scheme must not also reverse
        # the test fixture generated from SEAMARK_SCHEMES.
        cases = [
            ('lateral', 'port', 'red', None, 'can', 'lateral-port~can'),
            ('lateral', 'starboard', 'green', None, 'conical', 'lateral-starboard~cone'),
            ('lateral', 'preferred_channel_starboard', 'red;green;red', 'horizontal',
             'can', 'preferred-channel-starboard~can'),
            ('lateral', 'preferred_channel_port', 'green;red;green', 'horizontal',
             'conical', 'preferred-channel-port~cone'),
            ('cardinal', 'north', 'black;yellow', 'horizontal', 'pillar', 'cardinal-n~pillar'),
            ('cardinal', 'east', 'black;yellow;black', 'horizontal', 'spar', 'cardinal-e~spar'),
            ('cardinal', 'south', 'yellow;black', 'horizontal', 'pillar', 'cardinal-s~pillar'),
            ('cardinal', 'west', 'yellow;black;yellow', 'horizontal', 'spar', 'cardinal-w~spar'),
            ('safe_water', None, 'red;white', 'vertical', 'spherical', 'safe-water~sphere'),
            ('special_purpose', None, 'yellow', None, 'can', 'special~can'),
            ('isolated_danger', None, 'black;red;black', 'horizontal', 'pillar',
             'isolated-danger~pillar'),
        ]
        for family, category, colour, pattern, shape, expected in cases:
            for type_prefix in ('buoy_', 'beacon_'):
                type_ = type_prefix + family
                prefix = 'seamark:' + type_ + ':'
                tags = {'seamark:type': type_, prefix + 'colour': colour, prefix + 'shape': shape}
                if category is not None:
                    tags[prefix + 'category'] = category
                if pattern is not None:
                    tags[prefix + 'colour_pattern'] = pattern
                with self.subTest(tags=tags):
                    self.assertEqual(normalize(tags, Point(5, 43))[0][2]['icon'], expected)

    def test_all_schemes_shapes_and_explicit_topmarks(self):
        for (family, category), scheme in SEAMARK_SCHEMES.items():
            for beacon in (False, True):
                for shape, suffix in SEAMARK_SHAPES.items():
                    if family == 'lateral' and (shape == 'spherical' or
                            shape == ('conical' if category in ('port', 'preferred_channel_starboard') else 'can')):
                        continue
                    for topmark in (False, True):
                        tags = tags_for(family, category, shape, beacon, topmark)
                        result = normalize(tags, Point(5, 43))
                        with self.subTest(tags=tags):
                            self.assertEqual(len(result), 1)
                            kind, geometry, properties = result[0]
                            self.assertEqual(kind, 'beacon' if beacon else 'buoy')
                            self.assertEqual(geometry, Point(5, 43))
                            self.assertEqual(properties['icon'], scheme[0] + '~' + suffix + ('~topmark' if topmark else ''))
                            self.assertIs(properties['virtual'], False)

    def test_missing_and_contradictory_tags_are_not_corrected(self):
        for (family, category) in SEAMARK_SCHEMES:
            tags = tags_for(family, category, topmark=True)
            prefix = 'seamark:' + tags['seamark:type'] + ':'
            required = [prefix + 'colour', prefix + 'shape',
                        'seamark:topmark:shape', 'seamark:topmark:colour']
            if category is not None:
                required.append(prefix + 'category')
            if SEAMARK_SCHEMES[(family, category)][2]:
                required.append(prefix + 'colour_pattern')
            for key in required:
                missing = dict(tags)
                del missing[key]
                self.assertEqual(normalize(missing, Point(5, 43)), [], key)
            for key, value in [(prefix + 'colour', 'blue'), (prefix + 'shape', 'barrel'),
                               (prefix + 'system', 'iala-b'), (prefix + 'colour_pattern', 'diagonal'),
                               ('seamark:topmark:shape', 'unknown'), ('seamark:topmark:colour', 'blue'),
                               ('seamark:virtual', 'yes'), ('seamark:virtual', 'unknown')]:
                self.assertEqual(normalize({**tags, key: value}, Point(5, 43)), [], (key, value))
        for category, shape in [('port', 'conical'), ('starboard', 'can'),
                                ('preferred_channel_starboard', 'conical'), ('preferred_channel_port', 'can')]:
            self.assertEqual(normalize(tags_for('lateral', category, shape), Point(5, 43)), [])
        # Red/green horizontal bands alone never imply a preferred channel.
        tags = tags_for('lateral', 'preferred_channel_port')
        del tags['seamark:buoy_lateral:category']
        self.assertEqual(normalize(tags, Point(5, 43)), [])

    def test_rejected_seamarks_retain_original_tags_in_audit(self):
        cases = [tags_for('lateral', 'port', 'conical'), tags_for('cardinal', 'east')]
        del cases[1]['seamark:buoy_cardinal:colour']
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            pbf = directory / 'bad.osm.pbf'
            with osmium.SimpleWriter(str(pbf)) as writer:
                for id_, tags in enumerate(cases, 1):
                    writer.add_node(osmium.osm.mutable.Node(id=id_, location=(5, 43), tags=tags, version=1))
            with closing(ingest(pbf, directory / 'inventory.sqlite', [4, 42, 6, 44], {}, directory)) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM features').fetchone()[0], 0)
                rows = db.execute('SELECT tags,reason FROM skipped ORDER BY id').fetchall()
                self.assertEqual([json.loads(row[0]) for row in rows], cases)
                self.assertTrue(all('insufficient' in row[1] for row in rows))


class SpritesTest(unittest.TestCase):
    def test_generated_atlases_match_and_cover_every_mapping(self):
        one = json.loads((ROOT / 'assets/sprite.json').read_text())
        two = json.loads((ROOT / 'assets/sprite@2x.json').read_text())
        self.assertEqual(one.keys(), two.keys())
        for metadata in (one, two):
            for scheme in SEAMARK_SCHEMES.values():
                for shape in SEAMARK_SHAPES.values():
                    self.assertIn(scheme[0] + '~' + shape, metadata)
                    self.assertIn(scheme[0] + '~' + shape + '~topmark', metadata)
        for name in one:
            for field in ('x', 'y', 'width', 'height', 'pixelRatio'):
                self.assertEqual(two[name][field], one[name][field] * 2)
        # The tracked assets must be exactly reproducible from the generator.
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            (output / 'assets').mkdir()
            with patch('generate_demo.ROOT', output):
                sprites()
            for name in ('sprite.json', 'sprite@2x.json', 'sprite.png', 'sprite@2x.png'):
                self.assertEqual(digest(output / 'assets' / name), digest(ROOT / 'assets' / name))

    def test_colours_stripes_and_topmark_orientation_in_pixels(self):
        colours = {'black': (32, 38, 44), 'yellow': (217, 182, 76), 'red': (216, 73, 73),
                   'green': (46, 155, 104), 'white': (247, 247, 244)}
        for ratio, suffix in ((1, ''), (2, '@2x')):
            atlas = Image.open(ROOT / f'assets/sprite{suffix}.png')
            self.assertEqual(atlas.mode, 'RGBA')
            metadata = json.loads((ROOT / f'assets/sprite{suffix}.json').read_text())
            def tile(name):
                m = metadata[name]
                return np.array(atlas.crop((m['x'], m['y'], m['x'] + m['width'], m['y'] + m['height'])))
            def colour_at(name, x, y, expected):
                pixel = tile(name)[round(y * ratio / 2), round(x * ratio / 2)]
                self.assertGreater(pixel[3], 240)
                self.assertLess(np.linalg.norm(pixel[:3].astype(float) - colours[expected]), 35, (name, x, y, pixel))
            for direction, bands in {'n': [(40, 'black'), (58, 'yellow')],
                                     'e': [(40, 'black'), (49, 'yellow'), (58, 'black')],
                                     's': [(40, 'yellow'), (58, 'black')],
                                     'w': [(40, 'yellow'), (49, 'black'), (58, 'yellow')]}.items():
                for shape in SEAMARK_SHAPES.values():
                    for y, expected in bands:
                        colour_at('cardinal-' + direction + '~' + shape, 40, y, expected)
            for y in (40, 49, 58):
                for x, colour in ((30, 'red'), (36, 'white'), (42, 'red'), (48, 'white')):
                    colour_at('safe-water~can', x, y, colour)
            for name, colour in [('lateral-port', 'red'), ('lateral-starboard', 'green'),
                                 ('special', 'yellow')]:
                for shape in SEAMARK_SHAPES.values():
                    for y in (40, 49, 58):
                        colour_at(name + '~' + shape, 40, y, colour)
            for name, bands in [('isolated-danger', ('black', 'red', 'black')),
                                ('preferred-channel-starboard', ('red', 'green', 'red')),
                                ('preferred-channel-port', ('green', 'red', 'green'))]:
                for y, colour in zip((40, 49, 58), bands):
                    colour_at(name + '~can', 40, y, colour)
            for name in ('lateral-port', 'lateral-starboard', 'safe-water', 'special', 'isolated-danger',
                         'cardinal-n', 'cardinal-e', 'cardinal-s', 'cardinal-w'):
                # LANCZOS leaves faint ringing above the body, but no opaque topmark.
                self.assertLess(int(tile(name + '~pillar')[:int(32 * ratio / 2), :, 3].max()), 20)
                self.assertGreater(int(tile(name + '~pillar~topmark')[:int(32 * ratio / 2), :, 3].sum()), 0)
            # At 2x the 80px drawing is exact: an up cone widens downwards, a down cone narrows.
            if ratio == 2:
                for direction, orientations in {'n': (True, True), 'e': (True, False),
                                                's': (False, False), 'w': (False, True)}.items():
                    pixels = tile('cardinal-' + direction + '~pillar~topmark')
                    for y, up in zip((10, 22), orientations):
                        a, b = np.count_nonzero(pixels[y, :, 3]), np.count_nonzero(pixels[y + 4, :, 3])
                        self.assertGreater(b if up else a, a if up else b, direction)
            self.assertEqual(atlas.getpixel((0, 0))[3], 0)


class OSMOnlyTest(unittest.TestCase):
    def test_osm_only_preserves_shom_and_refuses_changed_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            region, catalog, sources = fixture(directory)
            output, cache = directory / 'data', directory / 'cache'
            old = prepare(region, sources, catalog, output, cache, 100, 16)
            old_dir = current_generation(output)
            old_contours = [f for f in iter_collection(old_dir / 'features.geojson') if f['properties']['kind'] == 'contour']
            # Never invoke either depth-grid construction or contour extraction in this mode.
            with (patch('regional_bathymetry.build_field', side_effect=AssertionError('SHOM rebuild')),
                 patch('regional_bathymetry.contours', side_effect=AssertionError('SHOM contours')),
                 patch('coastal_geometry.coastal_zone', side_effect=AssertionError('coastal buffer'))):
                new = prepare(region, sources, None, output, cache, 100, 16, osm_only=True)
            self.assertEqual(old['bathymetry'], new['bathymetry'])
            for name in ('bathymetry.json', 'water.geojson', 'coverage.geojson'):
                self.assertEqual(old['files_sha256'][name], new['files_sha256'][name])
            new_contours = [f for f in iter_collection(current_generation(output) / 'features.geojson') if f['properties']['kind'] == 'contour']
            self.assertEqual(old_contours, new_contours)
            old_vectors = [f for f in iter_collection(old_dir / 'features.geojson') if f['properties']['kind'] not in ('buoy', 'beacon')]
            new_vectors = [f for f in iter_collection(current_generation(output) / 'features.geojson') if f['properties']['kind'] not in ('buoy', 'beacon')]
            self.assertEqual(old_vectors, new_vectors)
            old_marks = [f for f in iter_collection(old_dir / 'features.geojson') if f['properties']['kind'] == 'buoy']
            new_marks = [f for f in iter_collection(current_generation(output) / 'features.geojson') if f['properties']['kind'] == 'buoy']
            self.assertEqual(old_marks, new_marks)
            changed = copy.deepcopy(region)
            changed['coverage']['sea_buffer_nm'] = 20
            with self.assertRaises(ValueError):
                prepare(changed, sources, None, output, cache, 100, 16, osm_only=True)
            original_sources = sources.read_text()
            changed_sources = json.loads(original_sources)
            changed_sources['osm']['sha256'] = '0' * 64
            sources.write_text(json.dumps(changed_sources))
            with self.assertRaises(ValueError):
                prepare(region, sources, None, output, cache, 100, 16, osm_only=True)
            sources.write_text(original_sources)
            (current_generation(output) / 'bathymetry.json').write_text('{}')
            with self.assertRaises(ValueError):
                prepare(region, sources, None, output, cache, 100, 16, osm_only=True)


if __name__ == '__main__':
    unittest.main()
