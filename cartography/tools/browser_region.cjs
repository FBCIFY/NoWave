// Observe the real Flutter Web client and regional endpoints; no library injection.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../test-results/france-med-real');
const scenes = [
  ['01-region', [5.35, 43.15], 7],
  ['02-marseille', [5.365, 43.293], 15.3],
  ['03-sete', [3.697, 43.399], 15.3],
  ['04-port-vendres', [3.107, 42.517], 15.3],
  ['05-nice', [7.286, 43.695], 15.3],
  ['06-nodata-east', [8.05, 43.75], 11],
];

(async () => {
  fs.mkdirSync(output, {recursive: true});
  const browser = await chromium.launch({headless: true,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 1100, height: 950}});
    const errors = [], requests = [], responses = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('request', request => requests.push(request.url()));
    page.on('response', response => {
      if (response.url().startsWith('http://127.0.0.1:8765/')) responses.push({
        url: response.url(), status: response.status(),
        bytes: Number(response.headers()['content-length'] || 0),
      });
    });
    await require('./browser_observe.cjs')(page, '__map');
    await page.goto(process.env.NOWAVE_WEB_URL || 'http://127.0.0.1:8766');
    await page.waitForFunction(() => window.__map?.loaded(), null, {timeout: 60000});
    const metadata = await page.evaluate(() => __map.getStyle().metadata);
    if (metadata['nowave:data_mode'] !== 'REGION_REAL' || metadata['nowave:region'] !== 'france_med') {
      throw Error('Expected genuine France Mediterranean style');
    }
    const results = [];
    for (const [name, center, zoom] of scenes) {
      await page.evaluate(({center, zoom}) => __map.jumpTo({center, zoom}), {center, zoom});
      await page.waitForFunction(() => __map.loaded(), null, {timeout: 60000});
      await page.waitForTimeout(1000);
      const rendered = await page.evaluate(() => [...new Set(__map.queryRenderedFeatures().map(f => f.layer.id))]);
      if (!name.includes('nodata') && !rendered.includes('coast')) throw Error(`${name}: coastline missing`);
      await page.screenshot({path: path.join(output, name + '.png')});
      results.push({name, center, zoom, rendered});
    }
    const before = await page.evaluate(() => __map.getCenter().toArray());
    await page.mouse.move(550, 500); await page.mouse.down();
    await page.mouse.move(650, 500, {steps: 12}); await page.mouse.up();
    await page.waitForTimeout(300);
    const after = await page.evaluate(() => __map.getCenter().toArray());
    await page.mouse.wheel(0, -180); await page.waitForTimeout(600);
    const zoom = await page.evaluate(() => __map.getZoom());
    if (before[0] === after[0] || zoom <= 11) throw Error('Pan/zoom failed');
    if (requests.some(url => /\/data\/demo|demo-bathymetry|mapbox\.com|maptiler\.com|maps\.google/.test(url))) {
      throw Error('Unexpected demo or proprietary map request');
    }
    for (const part of ['/data/france_med/water.geojson', '/tiles/vector/france_med/',
                        '/tiles/bathymetry/france_med/', '/assets/sprite', '/assets/font/']) {
      if (!responses.some(r => r.url.includes(part) && r.status === 200)) throw Error('Not loaded: ' + part);
    }
    const failed = responses.filter(r => ![200, 204].includes(r.status));
    const result = {client: 'Actual Flutter Web / MapLibreJsSource.cdn()', metadata,
      errors, mapErrors: await page.evaluate(() => __mapErrors), failed,
      responses, bytesServed: responses.reduce((sum, r) => sum + r.bytes, 0),
      pan: true, zoom: true, scenes: results,
      note: 'HTTP 204 tiles are intentionally absent NoData, never invented depth; this is not a native mobile test'};
    fs.writeFileSync(path.join(output, 'browser-result.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify({errors, failed, bytesServed: result.bytesServed, scenes: results}, null, 2));
    if (errors.length || failed.length || result.mapErrors.length) {
      throw Error('Client/MapLibre/network failures; inspect browser-result.json');
    }
  } finally {await browser.close();}
})().catch(error => {console.error(error); process.exit(1);});
