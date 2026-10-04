// Exercise the genuine Flutter/CDN path; Cassis is an additional scenario.
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const output = path.resolve(__dirname, '../previews/cassis-real');
const scenes = [
 ['01-cassis-approach', [5.536,43.2085],14.35,['coast','contours','port-symbols']],
 ['02-cassis-port', [5.5362,43.2134],15.9,['coast','pontoons','light-symbols','port-symbols']],
 ['03-cassis-marina-detail', [5.5360,43.2140],17.35,['coast','pontoons','light-symbols']]
];
(async()=>{
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:1100,height:950},deviceScaleFactor:1});
  const errors=[],dem=[],local=[];
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  page.on('response',r=>{
   if(r.url().includes('elevation-tiles-prod/terrarium/'))dem.push({url:r.url(),status:r.status()});
   if(r.url().includes('/data/cassis/')||r.url().includes('cassis-bathymetry.png'))local.push({url:r.url(),status:r.status()});
  });
  await require('./browser_observe.cjs')(page,'__map');
  await page.goto('http://127.0.0.1:8766');
  await page.waitForFunction(()=>window.__map?.loaded(),null,{timeout:60000});
  const metadata=await page.evaluate(()=>__map.getStyle().metadata);
  if(metadata['nowave:data_mode']!=='CASSIS_REAL')throw Error('Expected genuine Cassis real style');
  const results=[];
  for(const [name,center,zoom,required] of scenes){
   await page.evaluate(({center,zoom})=>__map.jumpTo({center,zoom}),{center,zoom});
   await page.waitForFunction(()=>__map.loaded(),null,{timeout:60000});
   await page.waitForTimeout(1600);
   const rendered=await page.evaluate(()=>[...new Set(__map.queryRenderedFeatures().map(f=>f.layer.id))]);
   for(const layer of required)if(!rendered.includes(layer))throw Error(`${name}: missing ${layer}; visible ${rendered}`);
   await page.screenshot({path:path.join(output,name+'.png')});
   results.push({name,center,zoom,rendered});
  }
  const featureData=await page.evaluate(()=>__map.getStyle().sources.features.data);
  if(typeof featureData==='string'){
   if(!featureData.includes('/data/cassis/'))throw Error('Unexpected feature source');
  }else if(!featureData.features?.length||featureData.features.some(f=>f.properties.demo!==false)){
   throw Error('Unexpected real features');
  }
  await page.evaluate(()=>__map.jumpTo({center:[5.536,43.2095],zoom:14.5}));
  await page.waitForFunction(()=>__map.loaded(),null,{timeout:60000});
  await page.waitForTimeout(1300);
  const water=await page.evaluate(async()=>{
   const source=__map.getStyle().sources['relief-sea-mask'];
   const data=typeof source.data==='string'?await (await fetch(source.data)).json():source.data;
   const project=coords=>coords.map(p=>{const q=__map.project(p);return[q.x,q.y]});
   const geometry=data.geometry;
   return {type:geometry.type,coordinates:geometry.type==='Polygon'?geometry.coordinates.map(project):geometry.coordinates.map(p=>p.map(project))};
  });
  fs.writeFileSync(path.join(output,'water-screen.json'),JSON.stringify(water));
  await page.evaluate(()=>__map.setLayoutProperty('land-relief','visibility','none'));
  await page.waitForTimeout(900);
  await page.locator('.maplibregl-canvas').screenshot({path:path.join(output,'sea-without-hillshade.png')});
  await page.evaluate(()=>__map.setLayoutProperty('land-relief','visibility','visible'));
  await page.waitForTimeout(900);
  await page.locator('.maplibregl-canvas').screenshot({path:path.join(output,'sea-with-hillshade.png')});
  const pixelCheck=JSON.parse(execFileSync(process.env.NOWAVE_PYTHON||'python3',
   [path.join(__dirname,'check_cassis_sea.py'),output],{encoding:'utf8'}));
  const before=await page.evaluate(()=>__map.getCenter().toArray());
  await page.mouse.move(550,500);await page.mouse.down();await page.mouse.move(640,500,{steps:12});await page.mouse.up();await page.waitForTimeout(600);
  const after=await page.evaluate(()=>__map.getCenter().toArray());
  await page.mouse.wheel(0,-180);await page.waitForTimeout(1000);
  const zoom=await page.evaluate(()=>__map.getZoom());
  const mapErrors=await page.evaluate(()=>__mapErrors);
  for(const part of ['features.geojson','water.geojson','cassis-bathymetry.png'])
   if(!local.some(r=>r.url.includes(part)&&r.status===200))throw Error('Not loaded: '+part);
  if(errors.length||mapErrors.length||!dem.length||dem.some(r=>r.status!==200)||local.some(r=>r.status!==200)||before[0]===after[0]||zoom<=14.5)throw Error(JSON.stringify({errors,mapErrors,dem:dem.length,before,after,zoom}));
  const result={loader:'Flutter MapLibreJsSource.cdn(), unchanged',metadata,errors,mapErrors,dem,local,pan:true,zoom:true,scenes:results,pixelCheck};
  fs.writeFileSync(path.join(output,'browser-result.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify({errors,mapErrors,demResponses:dem.length,local,pan:true,zoom:true,pixelCheck,scenes:results},null,2));
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
