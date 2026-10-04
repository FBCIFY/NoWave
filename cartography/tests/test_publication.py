"""Offline regressions for Cassis isolation, vector profiles and publication."""
from contextlib import closing, contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
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

from test_regions import ROOT, fixture, server
import build_style
import prepare_cassis
import prepare_region
import pipeline_io
from pipeline_io import atomic_json, current_generation, digest
from region_config import resolve_region

SCRIPT = ROOT / 'tools/build_vector_tiles.sh'
FORBIDDEN_REGIONAL = {'--no-line-simplification', '--no-tiny-polygon-reduction',
                      '--no-feature-limit', '--no-tile-size-limit'}


def hashes(directory):
    return {str(p.relative_to(directory)): digest(p) for p in directory.rglob('*') if p.is_file()}


def metadata(path):
    with closing(sqlite3.connect(path)) as db:
        return dict(db.execute('SELECT name,value FROM metadata'))


def build_vector(source, output, profile, **environment):
    return subprocess.run([str(SCRIPT), str(source), str(output), 'nowave', profile],
                          env={**os.environ, **environment}, capture_output=True, text=True, check=True)


class CassisGuardTest(unittest.TestCase):
    def setUp(self):
        self.before = hashes(ROOT / 'data/cassis')
        self.timestamps = {p: p.stat().st_mtime_ns for p in (ROOT / 'data/cassis').rglob('*') if p.is_file()}

    def tearDown(self):
        self.assertEqual(hashes(ROOT / 'data/cassis'), self.before)
        self.assertEqual({p: p.stat().st_mtime_ns for p in self.timestamps}, self.timestamps)

    def test_cassis_sources_catalog_output_resolution_block_size_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            output = str(Path(directory) / 'must-not-exist')
            for option, value in [('--sources', 'dummy'), ('--bathymetry-catalog', 'dummy'),
                                  ('--output', output), ('--resolution', '100'), ('--resolution', '10'),
                                  ('--block-size', '512'), ('--block-size', '16')]:
                with self.subTest(option=option, value=value):
                    result = subprocess.run([sys.executable, str(ROOT/'tools/prepare_region.py'),
                        '--region', 'cassis', option, value], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn('Cassis refuses regional options: ' + option, result.stderr)
            self.assertFalse(Path(output).exists())

    def test_direct_prepare_cassis_refused_before_any_io(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'output'
            with self.assertRaisesRegex(ValueError, 'prepare_cassis.py'):
                prepare_region.prepare(resolve_region('cassis'), None, None, output, Path(directory)/'cache')
            self.assertFalse(output.exists())

    def test_other_region_cannot_write_into_cassis_or_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            alias = Path(directory)/'alias'
            alias.symlink_to(ROOT/'data/cassis', target_is_directory=True)
            for output, cache in [(ROOT/'data/cassis', Path(directory)/'cache'),
                                  (alias/'child', Path(directory)/'cache'),
                                  (Path(directory)/'output', ROOT/'data/cassis/cache')]:
                with self.assertRaisesRegex(ValueError, 'must not overlap'):
                    prepare_region.prepare(resolve_region('france_med'), None, None, output, cache)

    def test_allowed_cassis_cli_always_calls_legacy_preparer(self):
        with patch.object(sys, 'argv', ['prepare_region.py', '--region', 'cassis', '--offline']), \
             patch.object(prepare_cassis, 'main') as legacy, \
             patch.object(prepare_region, 'prepare', side_effect=AssertionError('Generic pipeline called')):
            prepare_region.main()
            legacy.assert_called_once_with()
            self.assertEqual(sys.argv, ['prepare_cassis.py', '--region', str(ROOT/'regions/cassis.json'), '--offline'])


class VectorProfilesTest(unittest.TestCase):
    def test_regional_oversized_tile_fails_without_replacing_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root/'dense.geojson', root/'previous.mbtiles'
            first = {'type':'Feature', 'geometry':{'type':'Point','coordinates':[5.535,43.21]},
                     'properties':{'kind':'buoy', 'nav_id':0}}
            atomic_json(source, {'type':'FeatureCollection','features':[first]})
            build_vector(source, output, 'regional', MIN_ZOOM='6', MAX_ZOOM='6')
            previous = digest(output)
            features = [{**first, 'properties':{'kind':'buoy','nav_id':i,
                'source_note':hashlib.shake_256(str(i).encode()).hexdigest(1024)}} for i in range(1200)]
            atomic_json(source, {'type':'FeatureCollection','features':features})
            with self.assertRaises(subprocess.CalledProcessError):
                build_vector(source, output, 'regional', MIN_ZOOM='6', MAX_ZOOM='6')
            self.assertEqual(digest(output), previous)
            self.assertEqual(list(root.glob('previous.mbtiles.*.mbtiles')), [])

    def test_real_build_profiles_metadata_options_and_point_retention(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root/'points.geojson'
            features = [{'type':'Feature', 'properties':{'kind':'buoy', 'icon':'cardinal-n', 'nav_id':i},
                         'geometry':{'type':'Point','coordinates':[5.535 + i*.000001,43.21]}}
                        for i in range(48)]
            atomic_json(source, {'type':'FeatureCollection','features':features})
            # Log the actual argv, then execute the real Tippecanoe binary.
            real = shutil.which('tippecanoe')
            wrapper = root/'tippecanoe'
            wrapper.write_text(f'#!{sys.executable}\nimport json,os,sys\n'
                'with open(os.environ["NOWAVE_TEST_ARGV"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
                f'os.execv({real!r}, [{real!r}, *sys.argv[1:]])\n')
            wrapper.chmod(0o755)
            log = root/'argv.jsonl'
            env = {'PATH':str(root)+os.pathsep+os.environ['PATH'], 'NOWAVE_TEST_ARGV':str(log)}
            for profile, zmin, zmax, overrides in [('cassis',6,18,{'MIN_ZOOM':'8','MAX_ZOOM':'9'}),
                ('regional',6,14,{'MIN_ZOOM':'6','MAX_ZOOM':'14'}),
                ('regional',8,11,{'MIN_ZOOM':'8','MAX_ZOOM':'11'})]:
                with self.subTest(profile=profile, zmin=zmin, zmax=zmax):
                    output = root/f'{profile}-{zmax}.mbtiles'
                    build_vector(source,output,profile,**env,**overrides)
                    md=metadata(output)
                    self.assertEqual(md['nowave:build_profile'],profile)
                    self.assertEqual(md['nowave:input_sha256'],digest(source))
                    self.assertIn('tippecanoe',md['nowave:tippecanoe_version'])
                    for prefix in ('','nowave:'):
                        self.assertEqual(int(md[prefix+'minzoom']),zmin)
                        self.assertEqual(int(md[prefix+'maxzoom']),zmax)
                    self.assertIn('nowave',[l['id'] for l in json.loads(md['json'])['vector_layers']])
                    server.validate_mbtiles(output)
                    args=[json.loads(line) for line in log.read_text().splitlines() if line != '["--version"]'][-1]
                    if profile=='cassis':
                        self.assertTrue(FORBIDDEN_REGIONAL.issubset(args))
                        # Tile payloads equal a direct invocation of the exact historical recipe.
                        reference=root/'historical.mbtiles'
                        subprocess.run([real,'-o',str(reference),'-l','nowave','-Z6','-z18',
                            *sorted(FORBIDDEN_REGIONAL),str(source)],check=True,capture_output=True)
                        with closing(sqlite3.connect(output)) as actual, closing(sqlite3.connect(reference)) as old:
                            query='SELECT zoom_level,tile_column,tile_row,tile_data FROM tiles ORDER BY 1,2,3'
                            self.assertEqual(actual.execute(query).fetchall(),old.execute(query).fetchall())
                    else:
                        self.assertFalse(FORBIDDEN_REGIONAL.intersection(args))
                        self.assertIn('--simplify-only-low-zooms',args)
                        self.assertIn('--maximum-tile-bytes=500000',args)
                        with closing(sqlite3.connect(output)) as db:
                            self.assertLessEqual(db.execute('SELECT MAX(length(tile_data)) FROM tiles').fetchone()[0],500000)
                        # Decode every tile at min/max zoom: crowded nautical points survive both.
                        decoded=json.loads(subprocess.check_output(['tippecanoe-decode',str(output)],text=True))
                        for zoom in (zmin,zmax):
                            ids={f['properties']['nav_id'] for tile in decoded['features']
                                 if tile['properties']['zoom']==zoom for layer in tile['features']
                                 for f in layer['features']}
                            self.assertEqual(ids,set(range(48)))

    def test_historical_default_and_explicit_profile_requirement(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            script=root/'tools/build_vector_tiles.sh'
            script.parent.mkdir()
            shutil.copyfile(SCRIPT,script)
            script.chmod(0o755)
            (root/'data/cassis').mkdir(parents=True)
            source=root/'data/cassis/features.geojson'
            atomic_json(source,{'type':'FeatureCollection','features':[{'type':'Feature',
                'geometry':{'type':'Point','coordinates':[5.535,43.21]},'properties':{'kind':'light'}}]})
            subprocess.run([str(script)],check=True,capture_output=True)
            self.assertEqual(metadata(root/'tiles/vector/cassis.mbtiles')['nowave:build_profile'],'cassis')
            bad=subprocess.run([str(script),str(source),str(root/'other.mbtiles')],capture_output=True,text=True)
            self.assertNotEqual(bad.returncode,0)
            self.assertIn('Specify build profile explicitly',bad.stderr)
            self.assertFalse((root/'other.mbtiles').exists())


class GenerationPublicationTest(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name)
        self.region,self.catalog,self.sources=fixture(self.root)
        self.region['id']='france_med'  # Fixture-only config, patched into style resolution.
        self.output=self.root/'data/france_med'
        self.cache=self.root/'cache'
        self.manifest_a=self.prepare()
        self.generation_a=current_generation(self.output)
        self.hashes_a=hashes(self.generation_a)

    def prepare(self):
        return prepare_region.prepare(self.region,self.sources,self.catalog,self.output,self.cache,100,16)

    def assert_current_consistent(self,manifest):
        current=current_generation(self.output)
        self.assertEqual(current.name,manifest['generation_id'])
        self.assertEqual(json.loads((current/'manifest.json').read_text()),manifest)
        self.assertEqual({name:digest(current/name) for name in manifest['files_sha256']},manifest['files_sha256'])
        return current

    @contextmanager
    def http(self):
        config=type('Config',(),dict(region='france_med',real_cassis=False,mbtiles=None,public_url=None,
                    bathymetry_tiles=None,relief_tiles=None,attribution=None,center=None))()
        with patch.object(server,'ROOT',self.root), patch.object(build_style,'ROOT',self.root), \
             patch('region_config.resolve_region',return_value=self.region):
            httpd=ThreadingHTTPServer(('127.0.0.1',0),server.handler_class(config))
            thread=threading.Thread(target=httpd.serve_forever,daemon=True)
            thread.start()
            try:
                yield f'http://127.0.0.1:{httpd.server_port}'
            finally:
                httpd.shutdown()
                httpd.server_close()
                thread.join()

    def test_generation_failure_after_water_keeps_published_a_and_http_style(self):
        from build_bathymetry_tiles import build_region_tiles
        tiles=self.root/'tiles/bathymetry/france_med'
        build_region_tiles(self.generation_a/'bathymetry.json',self.region['bbox'],tiles,10,11)
        build_vector(self.generation_a/'features.geojson',self.root/'tiles/vector/france_med.mbtiles',
                     'regional',MIN_ZOOM='6',MAX_ZOOM='11')
        original=atomic_json
        def fail_after_water(path,value):
            original(path,value)
            if path.name=='water.geojson':
                self.assertTrue(path.parent.name.startswith('.staging-'))
                self.assertFalse((path.parent/'manifest.json').exists())
                self.assertEqual(current_generation(self.output),self.generation_a)
                raise RuntimeError('artificial generation failure after water')
        with patch.object(pipeline_io,'atomic_json',side_effect=fail_after_water):
            with self.assertRaisesRegex(RuntimeError,'generation failure after water'):
                self.prepare()
        self.assert_current_consistent(self.manifest_a)
        self.assertEqual(hashes(self.generation_a),self.hashes_a)
        self.assertFalse(list((self.output/'generations').glob('.staging-*')))
        with self.http() as base:
            for name in ('water.geojson','manifest.json'):
                with urlopen(base+'/data/france_med/'+name) as response:
                    self.assertEqual(response.read(),(self.generation_a/name).read_bytes())
            with urlopen(base+'/style.json') as response:
                style=json.load(response)
                self.assertEqual(style['sources']['features']['maxzoom'],11)
                self.assertEqual(style['sources']['features']['minzoom'],6)
                self.assertEqual(style['center'],self.region['center'])

    def test_successful_generation_publish_switches_all_files_without_mixing(self):
        source_data=json.loads(self.sources.read_text())
        source_data['land']['source']='OFFLINE TEST GENERATION B'
        atomic_json(self.sources,source_data)
        old_replace=os.replace
        commit_observed=[]
        def observe_publish(src,dst):
            if Path(dst)==self.output/'current':
                self.assertEqual(current_generation(self.output),self.generation_a)
                self.assertEqual(hashes(self.generation_a),self.hashes_a)
                candidate=Path(src).resolve()
                candidate_manifest=json.loads((candidate/'manifest.json').read_text())
                for name,sha in candidate_manifest['files_sha256'].items():
                    self.assertEqual(digest(candidate/name),sha)
                commit_observed.append(candidate)
            old_replace(src,dst)
        with patch.object(pipeline_io.os,'replace',side_effect=observe_publish):
            manifest_b=self.prepare()
        generation_b=self.assert_current_consistent(manifest_b)
        self.assertNotEqual(generation_b,self.generation_a)
        self.assertEqual(commit_observed,[generation_b])
        self.assertEqual(hashes(self.generation_a),self.hashes_a)
        self.assertNotEqual(digest(generation_b/'water.geojson'),self.hashes_a['water.geojson'])
        self.assertNotEqual(manifest_b['features_sha256'],self.manifest_a['features_sha256'])
        with self.http() as base:
            for name in ('water.geojson','manifest.json'):
                with urlopen(base+'/data/france_med/'+name) as response:
                    self.assertEqual(response.read(),(generation_b/name).read_bytes())
            for path in ('generations/'+generation_b.name+'/manifest.json','current/manifest.json'):
                with self.assertRaises(HTTPError) as error:
                    urlopen(base+'/data/france_med/'+path)
                self.assertEqual(error.exception.code,404)
                error.exception.close()

    def test_validation_failure_before_publish_keeps_current(self):
        original=prepare_region._prepare_generation
        def corrupt_staging(*args):
            manifest=original(*args)
            (args[3]/'features.geojson').write_text('{"incomplete":')
            return manifest
        with patch.object(prepare_region,'_prepare_generation',side_effect=corrupt_staging):
            with self.assertRaises(ValueError):
                self.prepare()
        self.assert_current_consistent(self.manifest_a)
        self.assertEqual(hashes(self.generation_a),self.hashes_a)

    def test_pointer_replace_failure_keeps_previous_generation(self):
        original = os.replace
        def fail_pointer(src, dst):
            if Path(dst) == self.output/'current':
                raise OSError('artificial publish failure')
            original(src, dst)
        with patch.object(pipeline_io.os, 'replace', side_effect=fail_pointer):
            with self.assertRaisesRegex(OSError, 'publish failure'):
                self.prepare()
        self.assert_current_consistent(self.manifest_a)
        self.assertEqual(hashes(self.generation_a), self.hashes_a)
        self.assertFalse(list(self.output.glob('.current-*')))


if __name__=='__main__':
    unittest.main()
