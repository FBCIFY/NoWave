const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {validateStyleMin} = require('@maplibre/maplibre-gl-style-spec');
const root = path.resolve(__dirname, '..');
const template = JSON.parse(fs.readFileSync(path.join(root, 'style.json')));
const vector = JSON.parse(execFileSync('python3', ['-c',
  "import json, server; print(json.dumps(server.make_style('http://localhost', 'test.mbtiles', 'http://localhost/bathy/{z}/{x}/{y}.png', 'http://localhost/relief/{z}/{x}/{y}.png', 'Test source', relief_attribution='Test DEM source')))"
], {cwd: root}));
const preview = JSON.parse(execFileSync('python3', ['-c',
  "import json, server; print(json.dumps(server.make_style('http://localhost', relief_preview=True)))"
], {cwd: root}));
const cassis = JSON.parse(execFileSync('python3', ['-c',
  "import json, server; print(json.dumps(server.make_style('http://localhost', real_cassis=True)))"
], {cwd: root}));
const franceMed = JSON.parse(execFileSync('python3', ['-c',
  "import json; from tools.build_style import build_real_area, region_profile; import sys; sys.path.insert(0,'tools'); manifest=json.load(open('tests/fixtures/france-med-manifest.json')); print(json.dumps(build_real_area(region_profile('france_med', manifest, {'minzoom':6,'maxzoom':11,'field_signature':'fixture-only'}))))"
], {cwd: root}));
for (const [name, style] of [['demo', template], ['vector+DEM', vector], ['real-preview', preview], ['cassis-real', cassis], ['france-med-offline-profile', franceMed]]) {
  const errors = validateStyleMin(style);
  if (errors.length) {
    for (const error of errors) console.error(`${name}: ${error.message}`);
    process.exitCode = 1;
  } else console.log(`${name}: valid MapLibre v8 style (${style.layers.length} layers)`);
}
