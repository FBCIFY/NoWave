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

test('supported report categories and neutral fallback receive sprites', () => {
  const names = [];
  const drawing = new Proxy({
    getImageData() { return { width: 96, height: 112, data: new Uint8ClampedArray(96 * 112 * 4) }; },
  }, { get(target, key) { return target[key] || (() => {}); } });
  const context = { window: {}, document: { createElement() { return { width: 0, height: 0, getContext() { return drawing; } }; } }, Uint8ClampedArray };
  load('marker-icons.js', context);
  assert.equal(context.window.NoWaveMarkerIcons.install({ addImage(name) { names.push(name); } }), true);
  assert.deepEqual(names, ['report-marine_animal', 'report-obstruction', 'report-pollution', 'report-unknown']);
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

test('canvas receives exact category colors and original centered glyph geometry', () => {
  const draws=[], registered=[];let current;
  const context={window:{},Uint8ClampedArray,document:{createElement(){
    current={fills:[],arcs:[],curves:[],scales:[]};draws.push(current);const own=current;
    const drawing=new Proxy({fill(){own.fills.push(this.fillStyle);},arc(...v){own.arcs.push(v);},bezierCurveTo(...v){own.curves.push(v);},scale(...v){own.scales.push(v);},getImageData(){return {width:96,height:112};}},{get:(t,k)=>t[k]||(()=>{})});
    return {getContext:()=>drawing};
  }}};
  load('marker-icons.js',context);context.window.NoWaveMarkerIcons.install({addImage(...v){registered.push(v);}});
  assert.deepEqual(draws.map(d=>d.fills[0]),['#06B6D4','#F97316','#7C3AED','#64748B']);
  for(const d of draws) {assert.deepEqual(d.scales,[[2,2]]);assert.deepEqual(d.arcs[0].slice(0,3),[24,28,18]);}
  assert.equal(draws[0].curves.length,13);assert.equal(draws[2].curves.length,2);
  assert.ok(registered.every(r=>r[1].width===96&&r[1].height===112&&r[2].pixelRatio===2));
});

test('cold land and relief paint, water, coast and GEBCO contract reach Mapbox',()=>{
  const paint={},layers=[],sources={};
  const base=[{id:'background',type:'background'},{id:'water',type:'fill','source-layer':'water'},{id:'road',type:'line'},{id:'label',type:'symbol'}];
  const map={setFog(){},setLayoutProperty(){},setPaintProperty(id,k,v){paint[`${id}:${k}`]=v;},getSource(){},getLayer(){},getStyle:()=>({sources:{composite:{type:'vector'}},layers:base}),addSource(id,v){sources[id]=v;},addLayer(l,before){layers.push([l,before]);}};
  const c={window:{}};load('maritime-style.js',c);c.window.NoWaveMaritimeStyle.apply(map);
  assert.equal(paint['background:background-color'],'#354b60');assert.equal(paint['water:fill-color'],'#002D51');
  const land=layers.find(([l])=>l.id==='nowave-landcover');const relief=layers.find(([l])=>l.id==='nowave-land-relief');
  assert.equal(land[1],'water');assert.equal(relief[1],'water');
  assert.deepEqual(JSON.parse(JSON.stringify(relief[0].paint)),{'fill-color':['match',['get','class'],'shadow','#263d52','highlight','#91a9bb','rgba(0,0,0,0)'],'fill-opacity':.4});
  assert.match(JSON.stringify(land),/#344f58.*#48616b.*#566e79.*#657b87.*#c7d5df/);
  assert.equal(sources['nowave-seafloor'].maxzoom,6);const sea=layers.find(([l])=>l.id==='nowave-seafloor');assert.equal(sea[0].maxzoom,8);assert.equal(sea[1],'road');
  assert.deepEqual(Array.from(sea[0].paint['raster-opacity'].slice(3)),[0,1,6,1,8,0]);
  assert.equal(layers.at(-1)[0].id,'nowave-coastline');assert.equal(layers.at(-1)[0].paint['line-color'],'#d8e4ed');
});
