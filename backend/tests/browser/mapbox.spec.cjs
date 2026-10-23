const {test,expect}=require('@playwright/test');
const id=n=>`00000000-0000-0000-0000-${n.toString(16).padStart(12,'0')}`;
test('real Mapbox, GEBCO and canvas render all four views on isolated SQL',async({page},info)=>{
  test.skip(!process.env.NOWAVE_MAPBOX_CONFIG,'Live Mapbox requires an explicitly supplied public token file');
  test.setTimeout(90000);
  const errors=[],failed=[],emptyTerrainTiles=[],resourceChecks=[];
  page.on('pageerror',e=>errors.push(e.name));
  page.on('response',r=>{if(r.status()>=400)resourceChecks.push((async()=>{
    const u=new URL(r.url());
    // Empty ocean terrain tiles are accepted only with this verified API payload.
    if(r.status()===404 && u.hostname==='api.mapbox.com' && u.pathname.startsWith('/v4/mapbox.mapbox-terrain-v2/') && (await r.json()).message==='Tile not found') emptyTerrainTiles.push(u.pathname);
    else failed.push(`${r.status()} ${u.hostname}${u.pathname}`);
  })());});
  await page.addInitScript(()=>{
    window.__nativeMaps=[];let library;
    Object.defineProperty(window,'mapboxgl',{configurable:true,get:()=>library,set(value){
      library=value;const Original=value.Map;
      value.Map=class extends Original {
        constructor(options){super({...options,preserveDrawingBuffer:true});this.testColors={};this.testErrors=[];window.__nativeMaps.push(this);this.on('error',e=>this.testErrors.push(e.error?.name||'MapError'));}
        addImage(name,img,options){if(img.data){const p=(24*img.width+48)*4;this.testColors[name]=Array.from(img.data.slice(p,p+4));}return super.addImage(name,img,options);}
      };
    }});
  });
  await page.goto('/admin/login');await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0]?.isStyleLoaded()),{timeout:30000}).toBe(true);
  await page.locator('#email').focus();const lng=await page.evaluate(()=>window.__nativeMaps[0].getCenter().lng);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__nativeMaps[0].getCenter().lng)).toBeCloseTo(lng,3);
  await page.locator('#password-toggle').focus();await page.waitForTimeout(1300);expect(await page.evaluate(()=>window.__nativeMaps[0].getCenter().lng)).toBeLessThan(lng);
  await page.emulateMedia({reducedMotion:'reduce'});const stopped=await page.evaluate(()=>window.__nativeMaps[0].getCenter().lng);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__nativeMaps[0].getCenter().lng)).toBeCloseTo(stopped,3);
  await page.screenshot({path:`test-results/${info.project.name}-real-login.png`});
  await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('test-password');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page).toHaveURL(/\/admin$/);
  await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0]?.getLayer('points')?.id),{timeout:30000}).toBe('points');
  await expect(page.locator('#map-status')).toContainText('signalements dans la zone visible');
  await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0].queryRenderedFeatures({layers:['clusters']}).length),{timeout:20000}).toBeGreaterThan(0);
  const style=await page.evaluate(()=>{const m=window.__nativeMaps[0];return {colors:m.testColors,anchor:m.getLayoutProperty('points','icon-anchor'),layers:m.getStyle().layers.map(l=>l.id),bg:m.getPaintProperty('land','background-color'),pitch:m.getPitch(),bearing:m.getBearing()};});
  expect(style.colors['report-marine_animal']).toEqual([6,182,212,255]);expect(style.colors['report-obstruction']).toEqual([249,115,22,255]);expect(style.colors['report-pollution']).toEqual([124,58,237,255]);
  expect(style.anchor).toBe('center');expect(style.pitch).toBe(0);expect(style.bearing).toBe(0);expect(style.layers.indexOf('selected-icon')).toBeGreaterThan(style.layers.indexOf('cluster-count'));
  await page.screenshot({path:`test-results/${info.project.name}-real-surveillance.png`});
  const point=await page.evaluate(()=>{const m=window.__nativeMaps[0],f=m.queryRenderedFeatures({layers:['clusters']})[0],p=m.project(f.geometry.coordinates);return {x:p.x,y:p.y};});
  await page.mouse.click(point.x,point.y);await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0].getZoom())).toBeGreaterThan(2.4);
  await page.goto(`/admin?report=${id(5020)}`);await expect(page.locator('#report-detail img')).toBeVisible();await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0]?.getSource('selected')?._data?.features.length),{timeout:30000}).toBe(1);
  await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0].queryRenderedFeatures({layers:['selected-icon']}).length)).toBeGreaterThan(0);
  await page.waitForTimeout(600);await page.screenshot({path:`test-results/${info.project.name}-real-report.png`});
  await page.locator('#report-close').click();await page.getByRole('button',{name:'Utilisateurs',exact:true}).click();await page.getByRole('searchbox').fill('User 05');await page.locator('.user-row').filter({hasText:'User 05'}).click();await page.getByRole('button',{name:'Afficher les signalements'}).click();await expect(page.locator('.user-reports a')).toHaveCount(20);
  await page.getByRole('button',{name:'Page suivante',exact:true}).click();await expect(page.locator('.user-reports a')).toHaveCount(1);await page.screenshot({path:`test-results/${info.project.name}-real-users.png`});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.locator('#users-close').click();
  await page.route('**/admin/data/reports?*',route=>route.fulfill({json:{type:'FeatureCollection',features:[{type:'Feature',geometry:{type:'Point',coordinates:[-30,24]},properties:{id:'unknown-test',category:'unknown-future'}}],truncated:false}}));
  await page.evaluate(()=>window.__nativeMaps[0].jumpTo({center:[-30,24],zoom:4}));
  await expect.poll(()=>page.evaluate(()=>window.__nativeMaps[0].queryRenderedFeatures({layers:['points']}).filter(f=>f.properties.category==='unknown-future').length)).toBeGreaterThan(0);
  expect(await page.evaluate(()=>window.__nativeMaps[0].hasImage('report-unknown'))).toBe(true);
  await Promise.all(resourceChecks);
  await info.attach('empty-ocean-terrain-tiles',{body:JSON.stringify(emptyTerrainTiles),contentType:'application/json'});
  const mapErrors=await page.evaluate(()=>window.__nativeMaps.flatMap(m=>m.testErrors));expect(errors).toEqual([]);expect(failed).toEqual([]);expect(mapErrors).toEqual([]);
});
