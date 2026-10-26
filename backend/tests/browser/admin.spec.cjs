const {test,expect}=require('@playwright/test');
const id=n=>`00000000-0000-0000-0000-${n.toString(16).padStart(12,'0')}`;
// Real Chromium and app; only the Mapbox network/runtime is replaced for these DOM journeys.
async function mapDouble(page) {
  await page.route('**/admin-static/mapbox-gl.js',route=>route.fulfill({contentType:'application/javascript',body:`
    window.__maps=[];
    window.mapboxgl={supported:()=>true,AttributionControl:class {},Map:class {
      constructor(options){this.options=options;this.center={lng:options.center[0],lat:options.center[1]};this.zoom=options.zoom;this.events={};this.sources={};this.layers=[];this.images={};this.moves=[];this.touchZoomRotate={disableRotation(){}};window.__maps.push(this);setTimeout(()=>{this.emit('style.load');this.emit('load');},20);}
      on(name,layer,fn){(this.events[typeof layer==='string'?name+':'+layer:name]??=[]).push(fn||layer);}
      emit(name,event){for(const fn of this.events[name]||[])fn(event);}
      getCenter(){return this.center;}getZoom(){return this.zoom;}stop(){this.stopped=true;}
      easeTo(o){this.moves.push(o);if(o.center)this.center={lng:o.center[0],lat:o.center[1]};if(o.zoom)this.zoom=o.zoom;}
      jumpTo(options){this.easeTo(options);}
      addControl(){}resize(){}setBearing(){}setFog(){}setLayoutProperty(){}setPaintProperty(){}
      getStyle(){return {sources:{},layers:[{id:'water',type:'fill','source-layer':'water'},{id:'road',type:'line'}]};}
      getBounds(){return {getWest:()=>-70,getEast:()=>20,getSouth:()=>-20,getNorth:()=>60};}
      getSource(id){return this.sources[id];}getLayer(id){return this.layers.find(l=>l.id===id);}
      addSource(id,s){this.sources[id]={...s,setData(d){this.data=d;},getClusterExpansionZoom(id,fn){fn(null,8);}};}
      addLayer(l){this.layers.push(l);}addImage(id,img){this.images[id]=img;}
      zoomIn(){this.zoom++;}zoomOut(){this.zoom--;}
    }};` }));
}
async function login(page,{map=true}={}) {
  if(map)await mapDouble(page);
  await page.goto('/admin/login');await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('test-password');
  await page.getByRole('button',{name:'Se connecter'}).click();await expect(page).toHaveURL(/\/admin$/);
}
async function openUser(page,number) {
  await page.getByRole('button',{name:'Utilisateurs',exact:true}).click();
  await page.getByRole('searchbox').fill(`User ${String(number).padStart(2,'0')}`);
  await page.locator('.user-row').filter({hasText:`User ${String(number).padStart(2,'0')}`}).click();
  await page.getByRole('button',{name:'Afficher les signalements'}).click();
  await expect(page.locator('.user-reports')).toHaveAttribute('aria-busy','false');
}
const checks=[];
test.beforeEach(async({page},info)=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.name));
  page.on('console',m=>{if(m.type()==='error'&&!m.text().startsWith('Failed to load resource'))errors.push(m.text());});
  const expected=info.title.startsWith('login validates')?[401,403]:info.title.startsWith('synthetic moderation')?[400,403,422]:[];
  page.on('response',r=>{if(r.status()>=400&&!expected.includes(r.status()))errors.push(`HTTP ${r.status()} ${new URL(r.url()).pathname}`);});
  page.on('requestfailed',r=>{const code=r.failure()?.errorText;if(code!=='net::ERR_ABORTED'&&!(info.title.startsWith('network failure')&&code==='net::ERR_FAILED'))errors.push(`Transport ${code} ${new URL(r.url()).pathname}`);});
  checks.push([page,errors]);
});
test.afterEach(async({page})=>{expect(checks.find(x=>x[0]===page)[1]).toEqual([]);});

test('login validates identity, refuses non-admin and uses secure cookies',async({page,context})=>{
  await mapDouble(page);await page.goto('/admin');await expect(page).toHaveURL(/admin\/login/);
  await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('bad');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page.getByRole('alert')).toContainText('incorrect');
  await page.locator('#email').fill('user2@nowave.test');await page.locator('#password').fill('test-password');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page.getByRole('alert')).toContainText(/administration/);
  await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('test-password');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page).toHaveURL(/\/admin$/);
  const cookie=(await context.cookies()).find(c=>c.name==='__Host-nowave_admin_session');expect(cookie).toMatchObject({httpOnly:true,secure:true,sameSite:'Strict',path:'/'});
});

test('rotation pauses on typing and respects reduced motion without an extra control',async({page})=>{
  await mapDouble(page);await page.goto('/admin/login');await expect.poll(()=>page.evaluate(()=>window.__maps[0]?.moves.length)).toBeGreaterThan(0);
  await page.locator('#email').focus();const before=await page.evaluate(()=>window.__maps[0].moves.length);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__maps[0].moves.length)).toBe(before);
  await page.locator('#password-toggle').focus();await expect.poll(()=>page.evaluate(()=>window.__maps[0].moves.length)).toBeGreaterThan(before);
  await expect(page.locator('#rotation-toggle')).toHaveCount(0);
  await page.emulateMedia({reducedMotion:'reduce'});const stopped=await page.evaluate(()=>window.__maps[0].moves.length);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__maps[0].moves.length)).toBe(stopped);
  await page.emulateMedia({reducedMotion:'no-preference'});await expect.poll(()=>page.evaluate(()=>window.__maps[0].moves.length)).toBeGreaterThan(stopped);
});

for(const [number,count] of [[2,0],[3,1],[4,20],[5,21],[6,40],[7,41]])test(`real SQL pagination exposes all ${count} report links and keyboard navigation`,async({page})=>{
  await login(page);await openUser(page,number);let seen=[];
  for(let p=1;p<=Math.max(1,Math.ceil(count/20));p++) {
    await expect(page.locator('.user-reports')).toHaveAttribute('aria-busy','false');
    const links=await page.locator('.user-reports a').evaluateAll(as=>as.map(a=>a.getAttribute('href')));seen.push(...links);
    if(count>p*20){const next=page.getByRole('button',{name:'Page suivante',exact:true});await next.focus();await page.keyboard.press('Enter');await expect(page.locator('.user-reports')).toContainText(`Page ${p+1}`);}
  }
  expect(seen.length).toBe(count);expect(new Set(seen).size).toBe(count);
  if(count>=21)expect(seen).toContain(`/admin?report=${id(number*1000+count-21)}`);
  await expect(page.getByRole('button',{name:'Page suivante',exact:true})).toBeDisabled();
  await expect(page.locator('.user-reports')).toContainText(count?'Fin de la liste':'Aucun signalement');
  if(count===21){await page.locator('.user-reports a').first().click();await expect(page.locator('#report-detail')).toContainText('Synthetic report 5/0');}
});

test('search, user paging, filters and close/reopen reset the detail',async({page})=>{
  await login(page);await page.getByRole('button',{name:'Utilisateurs',exact:true}).click();await expect(page.locator('.user-row')).toHaveCount(20);
  await page.locator('#users-next').click();await expect(page.locator('#users-page')).toHaveText('2 / 2');await expect(page.locator('.user-row')).toHaveCount(8);
  await page.locator('#users-prev').click();await expect(page.locator('#users-page')).toHaveText('1 / 2');
  await page.locator('#user-status').selectOption('suspended');await expect(page.locator('#users-list')).toContainText('Aucun utilisateur');await page.locator('#user-status').selectOption('active');
  await page.getByRole('searchbox').fill('User 05');await page.locator('.user-row').filter({hasText:'User 05'}).click();await page.getByRole('button',{name:'Afficher les signalements'}).click();await expect(page.locator('.user-reports a')).toHaveCount(20);
  await page.locator('#users-close').click();await expect(page.locator('#users-panel')).toBeHidden();await page.getByRole('button',{name:'Utilisateurs',exact:true}).click();await expect(page.locator('#user-detail')).toBeEmpty();
});

test('network failure retry, delayed old user, navigation lock and expired session',async({page})=>{
  await login(page);let release, started;const pending=new Promise(r=>release=r), requested=new Promise(r=>started=r);
  await page.route(`**/admin/data/users/${id(5)}/reports*`,async route=>{started();await pending;await route.fulfill({json:{items:[{id:'stale',category:'stale'}],has_more:false}}).catch(()=>{});});
  await page.getByRole('button',{name:'Utilisateurs',exact:true}).click();await page.getByRole('searchbox').fill('User 05');await page.locator('.user-row').filter({hasText:'User 05'}).click();await page.getByRole('button',{name:'Afficher les signalements'}).click();await requested;
  await expect(page.getByRole('button',{name:'Page suivante',exact:true})).toBeDisabled();
  await page.getByRole('searchbox').fill('User 03');await page.locator('.user-row').filter({hasText:'User 03'}).click();await page.getByRole('button',{name:'Afficher les signalements'}).click();await expect(page.locator('.user-reports a')).toHaveCount(1);release();await page.waitForTimeout(100);await expect(page.locator('.user-reports')).not.toContainText('stale');
  await page.route(`**/admin/data/users/${id(3)}/reports*`,route=>route.abort('failed'),{times:1});await page.getByRole('button',{name:'Afficher les signalements'}).click();await page.getByRole('button',{name:'Réessayer'}).click();await expect(page.locator('.user-reports a')).toHaveCount(1);
  await page.context().clearCookies();await page.getByRole('button',{name:'Afficher les signalements'}).click();await expect(page.locator('.user-reports')).toContainText('Session expirée');
});

test('shared globe camera, clusters, selection, authorized/hidden/absent photo and panel close',async({page},info)=>{
  await login(page);await expect.poll(()=>page.evaluate(()=>window.__maps[0]?.sources.reports?.data.features.length)).toBeGreaterThan(0);
  expect(await page.evaluate(()=>window.__maps[0].options)).toMatchObject({center:[-20,25],projection:'globe',dragRotate:false,pitchWithRotate:false,maxPitch:0});
  await page.screenshot({path:`test-results/${info.project.name}-surveillance.png`});
  await page.evaluate(()=>window.__maps[0].emit('click:clusters',{features:[{properties:{cluster_id:7},geometry:{coordinates:[-30,24]}}]}));expect(await page.evaluate(()=>window.__maps[0].zoom)).toBe(8);
  await page.evaluate(r=>window.__maps[0].emit('click:points',{features:[{properties:{id:r,category:'pollution'},geometry:{coordinates:[-30,24]}}]}),id(5020));await expect(page.locator('#report-detail img')).toBeVisible();await expect(page.locator('#report-detail img')).toHaveJSProperty('naturalWidth',100);
  await page.screenshot({path:`test-results/${info.project.name}-report.png`});
  await page.locator('#report-close').click();await expect(page.locator('#report-panel')).toBeHidden();
  await page.goto(`/admin?report=${id(5019)}`);await expect(page.locator('#report-detail')).toContainText('Photo masquée');await expect(page.locator('#report-detail img')).toHaveCount(0);
  const hidden=await (await page.request.get(`/admin/data/reports/${id(5019)}`)).json();expect(hidden.photo.url).toBeNull();
  await page.goto(`/admin?report=${id(5018)}`);await expect(page.locator('#report-detail')).toContainText('Synthetic report');await expect(page.locator('#report-detail img')).toHaveCount(0);await expect(page.locator('#report-detail').getByRole('link',{name:'Masquer la photo'})).toHaveCount(0);
  await page.locator('#reset-map').click();expect(await page.evaluate(()=>window.__maps[0].center)).toEqual({lng:-20,lat:25});
});

test('no Mapbox token keeps login, lists and direct report operational without overflow',async({page},info)=>{
  await page.route('**/admin/login',async route=>{if(route.request().method()!=='GET')return route.continue();const r=await route.fetch();await route.fulfill({response:r,body:(await r.text()).replace(/data-token="[^"]*"/,'data-token=""')});});
  await page.route(/\/admin(?:\?.*)?$/,async route=>{if(route.request().method()!=='GET')return route.continue();const r=await route.fetch();await route.fulfill({response:r,body:(await r.text()).replace(/data-token="[^"]*"/,'data-token=""')});});
  await login(page);await page.goto('/admin');await expect(page.locator('#map-status')).toContainText('Carte indisponible');
  await page.goto(`/admin?report=${id(5018)}`);await expect(page.locator('#report-detail')).toContainText('Synthetic report');
  await openUser(page,5);await page.screenshot({path:`test-results/${info.project.name}-users.png`});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  const header=await page.locator('.surveillance-header').boundingBox();
  const panel=await page.locator('#users-panel').boundingBox();expect(panel.y).toBeGreaterThanOrEqual(header.y+header.height);expect(panel.x).toBeGreaterThanOrEqual(0);expect(panel.x+panel.width).toBeLessThanOrEqual(info.project.name==='mobile'?390:1440);
});

test('synthetic moderation enforces CSRF, reason and confirmation, then records real actions',async({page},info)=>{
  await login(page);const target=id(6000);const path=`/admin/actions/reports/${target}/remove`;await page.goto(path);
  const csrf=await page.locator('[name=csrf_token]').last().inputValue();
  expect((await page.request.post(path,{form:{reason:'Synthetic browser audit',confirmed:'yes',csrf_token:'forged'}})).status()).toBe(403);
  expect((await page.request.post(path,{form:{reason:'',confirmed:'yes',csrf_token:csrf}})).status()).toBe(422);
  expect((await page.request.post(path,{form:{reason:'Synthetic browser audit',csrf_token:csrf}})).status()).toBe(400);
  await page.locator('#reason').fill('Synthetic browser audit');await page.locator('[name=confirmed]').check();await page.getByRole('button',{name:'Confirmer l’action'}).click();await expect(page.locator('main')).toContainText('confirmé la réussite');
  const read=()=>page.request.get(`/admin/data/reports/${target}`).then(r=>r.json());expect((await read()).status).toBe('removed');
  await page.goto(`/admin/actions/reports/${target}/restore`);await page.locator('#reason').fill('Synthetic restore');await page.locator('[name=confirmed]').check();await page.getByRole('button',{name:'Confirmer l’action'}).click();expect((await read()).status).toBe('active');
  const photoId=id(info.project.name==='desktop'?7040:7039);
  await page.goto(`/admin/actions/reports/${photoId}/hide-photo`);await page.locator('#reason').fill('Synthetic photo moderation');await page.locator('[name=confirmed]').check();await page.getByRole('button',{name:'Confirmer l’action'}).click();await expect(page.locator('main')).toContainText('confirmé la réussite');
  const hidden=await (await page.request.get(`/admin/data/reports/${photoId}`)).json();expect(hidden.photo.url).toBeNull();expect(hidden.photo.hidden_at).toBeTruthy();
  await page.goto('/admin/audit');await expect(page.locator('main')).toContainText('Synthetic browser audit');
  for(const action of ['suspend','reactivate']){await page.goto(`/admin/actions/users/${id(2)}/${action}`);await page.locator('#reason').fill('Synthetic user moderation');await page.locator('[name=confirmed]').check();await page.getByRole('button',{name:'Confirmer l’action'}).click();await expect(page.locator('main')).toContainText('confirmé la réussite');}
});
