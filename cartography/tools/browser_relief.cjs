// Start map servers (8765 demo, 8767 --relief-preview) and Web build (8766).
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../../test-results/mapzen');
fs.mkdirSync(output, {recursive:true});
(async () => {
 const browser = await chromium.launch({headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader']});
 try {
  const page = await browser.newPage({viewport:{width:960,height:800},deviceScaleFactor:1});
  const errors=[], responses=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  page.on('response',r=>{if(r.url().startsWith('https://s3.amazonaws.com/elevation-tiles-prod/terrarium/'))responses.push({url:r.url(),status:r.status()});});
 await require('./browser_observe.cjs')(page, '__map');
  await page.route('http://127.0.0.1:8765/style.json',async route=>{
   const response=await page.request.get('http://127.0.0.1:8767/style.json');
   await route.fulfill({response});
  });
  await page.goto('http://127.0.0.1:8766');
  await page.waitForFunction(()=>window.__map?.loaded(),null,{timeout:60000});
  for(const [name,center,zoom] of [['cassis',[5.53,43.205],12],['la-ciotat',[5.605,43.174],12],['marseille',[5.37,43.30],12]]){
   await page.evaluate(({center,zoom})=>__map.jumpTo({center,zoom}),{center,zoom});
   await page.waitForFunction(()=>__map.loaded(),null,{timeout:60000});
   await page.waitForTimeout(1500);
   await page.evaluate(()=>__map.setLayoutProperty('land-relief','visibility','none'));
   await page.waitForTimeout(600);
   await page.screenshot({path:path.join(output,`${name}-before.png`)});
   await page.evaluate(()=>__map.setLayoutProperty('land-relief','visibility','visible'));
   await page.waitForTimeout(1000);
   await page.screenshot({path:path.join(output,`${name}-after.png`)});
  }
  const mapErrors=await page.evaluate(()=>__mapErrors);
  console.log({errors,mapErrors,loadedDemTiles:responses.length,httpStatuses:[...new Set(responses.map(r=>r.status))]});
  if(errors.length||mapErrors.length||!responses.length||responses.some(r=>r.status!==200))throw Error('DEM loading/rendering failed');
  const points=await page.evaluate(()=>{
   const rect=__map.getCanvas().getBoundingClientRect();
   return [[5.36,43.26],[5.39,43.27],[5.36,43.32]].map(lnglat=>{
    const p=__map.project(lnglat);return {lnglat,x:Math.round(p.x+rect.left),y:Math.round(p.y+rect.top)};
   });
  });
  fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({errors,mapErrors,demResponses:responses,marseilleSamplePoints:points},null,2));
  require('node:child_process').execFileSync(process.env.NOWAVE_PYTHON||'python3', [path.join(__dirname,'check_relief_pixels.py'),output],{stdio:'inherit'});
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
