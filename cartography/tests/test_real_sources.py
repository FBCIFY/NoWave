"""Offline reference-integrity and exact coastal-geometry checks, no downloads."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from coastal_geometry import line_buffer
from prepare_france_med_sources import complete_render_input, prepare, asset
from shapely.geometry import LineString, MultiLineString

OSMIUM = os.environ.get('NOWAVE_OSMIUM') or shutil.which('osmium')


class RealSourcesTest(unittest.TestCase):
    def test_native_tag_filter_keeps_areas_and_untagged_geometry_references(self):
        import osmium
        from regional_osm import extract_pbf, RELEVANT_KEYS, relevant
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'source.osm.pbf'
            with osmium.SimpleWriter(str(source)) as writer:
                for i, xy in enumerate([(5.50, 43.20), (5.54, 43.20),
                                         (5.54, 43.24), (5.50, 43.24)], 1):
                    writer.add_node(osmium.osm.mutable.Node(id=i, location=xy, version=1))
                writer.add_node(osmium.osm.mutable.Node(id=9, location=(5.52, 43.22), version=1))
                writer.add_way(osmium.osm.mutable.Way(id=10, nodes=[1, 2, 3, 4, 1],
                    tags={'natural': 'bay', 'name': 'TEST'}, version=1))
                for i, tags in [(99, {'type': 'multipolygon', 'natural': 'bay', 'name': 'TEST'}),
                                (100, {'type': 'multipolygon'})]:
                    writer.add_relation(osmium.osm.mutable.Relation(id=i, version=1,
                        members=[('w', 10, 'outer')], tags=tags))
            def objects(filtered):
                processor = osmium.FileProcessor(str(source)).with_areas()
                if filtered:
                    processor.with_filter(osmium.filter.KeyFilter(*RELEVANT_KEYS))
                return [(obj.type_str(), obj.id, dict(obj.tags)) for obj in processor
                        if relevant(dict(obj.tags))]
            self.assertEqual(objects(True), objects(False))
            cache = root / 'cache'
            cache.mkdir()
            extracted = extract_pbf(source, [5.51, 43.21, 5.53, 43.23], cache)
            ids = {(obj.type_str(), obj.id) for obj in osmium.FileProcessor(str(extracted))}
            self.assertTrue({('n', i) for i in range(1, 5)} <= ids)
            self.assertIn(('r', 99), ids)
            self.assertNotIn(('n', 9), ids)
            if any(t == 'a' and i == 201 for t, i, _ in objects(False)):
                self.assertIn(('r', 100), ids)  # Inherited tags must not filter out the raw relation.

    def test_spatial_prefilter_keeps_exact_coastal_geometry_and_excludes_inland(self):
        import sqlite3
        from shapely.geometry import Point, box, shape
        from pipeline_io import feature
        from regional_osm import features_in_zone
        with sqlite3.connect(':memory:') as db:
            db.execute('CREATE TABLE features (id, kind, payload)')
            inputs = [('1', 'buoy', Point(0, -1)), ('2', 'coastal_city', Point(0, 80)),
                      ('3', 'urban', box(-1, 0, 1, 4)),
                      ('4', 'coast', LineString([(-2, 0), (2, 0)]))]
            for id_, kind, geom in inputs:
                db.execute('INSERT INTO features VALUES (?,?,?)',
                           (id_, kind, json.dumps(feature(kind, geom, osm_id=id_))))
            output = list(features_in_zone(db, box(-2, -2, 2, 2), box(-2, 0, 2, 3),
                                           LineString([(-2, 0), (2, 0)])))
            self.assertEqual([f['properties']['kind'] for f in output], ['buoy', 'urban', 'coast'])
            self.assertTrue(shape(output[0]['geometry']).equals(Point(0, -1)))
            self.assertTrue(shape(output[1]['geometry']).equals(box(-1, 0, 1, 2)))
            self.assertTrue(shape(output[2]['geometry']).equals(inputs[3][2]))

    def test_batched_buffer_preserves_radius_and_geometry_without_simplifying(self):
        lines = MultiLineString([[(i * 1200, 0), (i * 1200 + 500, 300),
                                  (i * 1200 + 1000, 0)] for i in range(80)])
        for radius in (3000, 30 * 1852):
            expected = lines.buffer(radius)
            actual = line_buffer(lines, radius, batch_size=7)
            self.assertLess(actual.symmetric_difference(expected).area / expected.area, 1e-10)
        single = LineString([(0, 0), (1000, 0)])
        self.assertTrue(line_buffer(single, 55560).equals(single.buffer(55560)))

    @unittest.skipUnless(OSMIUM, 'osmium-tool required for reference-completion integration')
    def test_complete_pbf_preserves_multipolygon_and_audits_unsupported_dependencies(self):
        import osmium
        with tempfile.TemporaryDirectory() as temp:
            source, output = Path(temp) / 'source.osm.pbf', Path(temp) / 'complete.osm.pbf'
            with osmium.SimpleWriter(str(source)) as writer:
                for i, xy in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)], 1):
                    writer.add_node(osmium.osm.mutable.Node(id=i, location=xy, version=1))
                writer.add_way(osmium.osm.mutable.Way(id=10, nodes=[1, 2, 3, 4, 1], version=1))
                writer.add_relation(osmium.osm.mutable.Relation(id=100, version=1,
                    members=[('w', 10, 'outer')], tags={'type': 'multipolygon', 'natural': 'bay', 'name': 'TEST'}))
                writer.add_relation(osmium.osm.mutable.Relation(id=200, version=1,
                    members=[('w', 999, 'outer')], tags={'type': 'boundary'}))
                writer.add_relation(osmium.osm.mutable.Relation(id=201, version=1,
                    members=[('r', 200, '')], tags={'type': 'waterway'}))
            result = complete_render_input(source, output, OSMIUM)
            self.assertTrue(result['complete'])
            self.assertEqual({r['osm_id'] for r in result['excluded_relations']},
                             {'relation/200', 'relation/201'})
            objects = [(o.type_str(), o.id) for o in osmium.FileProcessor(str(output))]
            self.assertEqual(objects, [('n', 1), ('n', 2), ('n', 3), ('n', 4), ('w', 10), ('r', 100)])

    @unittest.skipUnless(OSMIUM, 'osmium-tool required for reference-completion integration')
    def test_incomplete_renderable_multipolygon_is_refused(self):
        import osmium
        with tempfile.TemporaryDirectory() as temp:
            source, output = Path(temp) / 'source.osm.pbf', Path(temp) / 'complete.osm.pbf'
            with osmium.SimpleWriter(str(source)) as writer:
                writer.add_relation(osmium.osm.mutable.Relation(id=100, version=1,
                    members=[('w', 999, 'outer')], tags={'type': 'multipolygon', 'natural': 'bay', 'name': 'TEST'}))
            with self.assertRaisesRegex(ValueError, 'Renderable relation/100 is incomplete'):
                complete_render_input(source, output, OSMIUM)
            self.assertFalse(output.exists())

    def test_reference_supplement_newer_than_snapshot_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            xml = root / 'reference.osm'
            xml.write_text('<osm version="0.6"><node id="1" version="1" timestamp="2026-10-04T00:00:00Z" lat="0" lon="0"/></osm>')
            entry = asset(xml, 'OFFLINE FIXTURE', 'TEST', '2026-10-04', name=xml.name, role='osm_references')
            lock = root / 'lock.json'
            lock.write_text(json.dumps(dict(assets=[entry], osm_timestamp='2026-10-03T20:20:50Z')))
            with self.assertRaisesRegex(ValueError, 'newer than the pinned snapshot'):
                prepare(root, lock, 'must-not-be-called')


if __name__ == '__main__':
    unittest.main()
