const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
function core() {
  const context = { window: { mapboxgl: { Map: function(options) { this.options = options; this.controls = []; this.addControl = (control, position) => this.controls.push({control, position}); }, AttributionControl: function(options) { this.options = options; } } } };
  vm.runInNewContext(fs.readFileSync('backend/app/web/static/map-core.js', 'utf8'), context);
  return context.window.NoWaveMapCore;
}
test('public and admin maps share globe, bounds, attribution and rotation policy', () => {
  const shared = core();
  const admin = shared.createMap({ container: 'admin', center: [0, 0], zoom: 2 });
  assert.equal(admin.options.projection, 'globe');
  assert.equal(admin.options.renderWorldCopies, false);
  assert.equal(admin.options.dragRotate, false);
  assert.equal(admin.options.attributionControl, false);
  assert.equal(admin.controls.length, 1);
  assert.equal(admin.controls[0].control.options.compact, false);
  assert.equal(admin.controls[0].position, 'bottom-right');
  assert.deepEqual(JSON.parse(JSON.stringify(admin.options.maxBounds)), [[-180,-85],[180,85]]);
  const guided = shared.createMap({ container: 'journey', maxPitch: 60, interactive: false, trackResize: false });
  assert.equal(guided.options.style, admin.options.style);
  assert.equal(guided.options.maxPitch, 60);
  assert.equal(guided.options.trackResize, false);
});
test('overview keeps the same center while shrinking to narrow or short viewports', () => {
  const shared = core();
  const desktop = shared.overview(1440, 1000);
  const mobile = shared.overview(390, 727);
  const landscape = shared.overview(844, 280);
  assert.equal(mobile.x, desktop.x);
  assert.equal(mobile.y, desktop.y);
  assert.equal(desktop.zoom, 1.75);
  assert.equal(mobile.zoom, 1.5 + Math.log2(350 / 600));
  assert.equal(shared.overview(320, 572).zoom, 0.5);
  assert(mobile.zoom < desktop.zoom);
  assert(landscape.zoom <= mobile.zoom);
  assert.equal(shared.overview(0, 0).zoom, 0.5);
  assert.equal(shared.overview(5000, 5000).zoom, 1.75);
});
