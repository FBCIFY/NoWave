const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');

function load(name, context) {
  const source = fs.readFileSync(`backend/app/web/static/${name}`, 'utf8');
  vm.runInNewContext(source, context, { filename: name });
}

test('bathymetry and fine coast remain below map labels', () => {
  const calls = { sources: [], layers: [] };
  const map = {
    setFog(fog) { calls.fog = fog; },
    setLayoutProperty() {}, setPaintProperty() {},
    getSource() { return undefined; }, getLayer() { return undefined; },
    getStyle() { return { sources: { composite: { type: 'vector' } }, layers: [
      { id: 'water', type: 'fill', 'source-layer': 'water' }, { id: 'road', type: 'line' },
      { id: 'label', type: 'symbol' },
    ] }; },
    addSource(id, source) { calls.sources.push([id, source]); },
    addLayer(layer, before) { calls.layers.push([layer, before]); },
  };
  const context = { window: {} }; load('maritime-style.js', context);
  context.window.NoWaveMaritimeStyle.apply(map, {login:true});
  assert.equal(calls.sources.find(x=>x[0]==='nowave-seafloor')[1].maxzoom, 6);
  assert.match(calls.sources.find(x=>x[0]==='nowave-seafloor')[1].tiles[0], /gebco-2026-v2/);
  assert.equal(calls.layers.find(x=>x[0].id==='nowave-seafloor')[1], 'road');
  assert.equal(calls.layers[0][1], 'water');
  assert.equal(calls.layers.find(x=>x[0].id==='nowave-coastline')[0].paint['line-width'][4], 0.45);
  assert.equal(calls.fog['star-intensity'], 0);
});

test('only supported report categories receive sprites', () => {
  const names = [];
  const drawing = new Proxy({
    getImageData() { return { width: 96, height: 112, data: new Uint8ClampedArray(96 * 112 * 4) }; },
  }, { get(target, key) { return target[key] || (() => {}); } });
  const context = { window: {}, document: { createElement() { return { width: 0, height: 0, getContext() { return drawing; } }; } }, Uint8ClampedArray };
  load('marker-icons.js', context);
  assert.equal(context.window.NoWaveMarkerIcons.install({ addImage(name) { names.push(name); } }), true);
  assert.deepEqual(names, ['report-marine_animal', 'report-obstruction', 'report-pollution']);
});

test('selected cluster expands through the Mapbox callback', () => {
  const context = { window: {}, Number, Array }; load('cluster-interaction.js', context);
  const movements = [];
  const map = {
    getSource(id) {
      assert.equal(id, 'reports');
      return { getClusterExpansionZoom(clusterId, callback) {
        assert.equal(clusterId, 7);
        callback(null, 5);
      } };
    },
    easeTo(options) { movements.push(options); },
  };
  context.window.NoWaveClusterInteraction.expand(map, {
    properties: { cluster_id: 7 }, geometry: { coordinates: [-28, 28] },
  });
  assert.equal(movements.length, 1);
  assert.equal(movements[0].zoom, 5);
  assert.deepEqual(Array.from(movements[0].center), [-28, 28]);
});
