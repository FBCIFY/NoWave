const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../previews/final-style');
const scenes = [
 ['01-global', [.025,.005],10.8, ['sea_name']],
 ['02-regional', [.032,.01],12, ['lighthouse-symbols','contours']],
 ['03-coastal', [.050,.009],13.5, ['buoy-symbols','anchorage-symbols','lighthouse-symbols','wreck-symbols','shoal-texture']],
 ['04-marina', [.037,-.0015],15.65, ['basins','pontoons','light-symbols','port-symbols','mooring-symbols']],
 ['05-dangers', [.067,.032],15, ['shoal-texture','reef-texture','wreck-symbols','contours']],
 ['06-reserve', [.0745,.053],14.2, ['reserve-area','reserve-outline','reserve-name']]
];
(async()=>{
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:960,height:850},deviceScaleFactor:1});
  const errors=[], dem=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('response',r=>{if(r.url().includes('elevation-tiles-prod/terrarium/'))dem.push({url:r.url(),status:r.status()});});
  await require('./browser_observe.cjs')(page,'__map');
  await page.goto('http://127.0.0.1:8766');
  await page.waitForFunction(()=>window.__map?.loaded(),null,{timeout:60000});
  const results=[];
  for(const [name,center,zoom,required] of scenes){
   await page.evaluate(({center,zoom})=>__map.jumpTo({center,zoom}),{center,zoom});
   await page.waitForFunction(()=>__map.loaded(),null,{timeout:60000});
   await page.waitForTimeout(1400);
   const rendered=await page.evaluate(()=>[...new Set(__map.queryRenderedFeatures().map(f=>f.layer.id))]);
   await page.screenshot({path:path.join(output,name+'.png')});
   for(const layer of required) if(!rendered.includes(layer)) throw Error(`${name}: missing ${layer}; visible ${rendered}`);
   await page.screenshot({path:path.join(output,name+'.png')});
   results.push({name,center,zoom,rendered});
  }
  const hierarchy=[];
  for(const level of [4,6,9,12,14,16,18]){
   await page.evaluate(zoom=>__map.jumpTo({center:[.054,0],zoom}),level);
   await page.waitForFunction(()=>__map.loaded(),null,{timeout:60000});
   await page.waitForTimeout(700);
   const visible=await page.evaluate(()=>[...new Set(__map.queryRenderedFeatures().map(f=>f.layer.id))]);
   if(level<=6 && visible.some(id=>id.endsWith('-symbols')||id==='coastal-major-roads'))throw Error('Low zoom overloaded');
   if(level<=12 && visible.includes('buoy-symbols'))throw Error('Buoys appeared too early');
   if(level===18 && !visible.includes('buoy-symbols'))throw Error('Close buoy details missing');
   hierarchy.push({zoom:level,visible});
  }
  await page.evaluate(()=>__map.jumpTo({center:[.0745,.053],zoom:14.2}));
  await page.waitForTimeout(800);
  const before=await page.evaluate(()=>__map.getCenter().toArray());
  await page.mouse.move(480,450);await page.mouse.down();await page.mouse.move(560,450,{steps:10});await page.mouse.up();await page.waitForTimeout(500);
  const after=await page.evaluate(()=>__map.getCenter().toArray());
  await page.mouse.wheel(0,-200);await page.waitForTimeout(1000);
  const finalZoom=await page.evaluate(()=>__map.getZoom());
  const mapErrors=await page.evaluate(()=>__mapErrors);
  if(errors.length||mapErrors.length||!dem.length||dem.some(r=>r.status!==200)||before[0]===after[0]||finalZoom<=14.2)throw Error(JSON.stringify({errors,mapErrors,dem:dem.length,before,after,finalZoom}));
  fs.writeFileSync(path.join(output,'browser-result.json'),JSON.stringify({loader:'Flutter MapLibreJsSource.cdn(), no library injection',errors,mapErrors,dem,pan:true,zoom:true,hierarchy,scenes:results},null,2)+'\n');
  console.log(JSON.stringify({errors,mapErrors,dem:dem.length,pan:true,zoom:true,hierarchy,scenes:results},null,2));
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
