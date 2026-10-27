const {test,expect}=require('@playwright/test');
const id=n=>`00000000-0000-0000-0000-${n.toString(16).padStart(12,'0')}`;
// Real Chromium, app, sessions and SQL; only provider boundaries are doubles.
async function mapDouble(page) {
  await page.route('**/admin-static/mapbox-gl.js',route=>route.fulfill({contentType:'application/javascript',body:`
    window.__maps=[];
    window.mapboxgl={supported:()=>true,AttributionControl:class {},Marker:class {
      constructor({element}){this.element=element;}
      setLngLat(value){this.location=value;return this;}
      addTo(map){document.getElementById(map.options.container).append(this.element);return this;}
      getElement(){return this.element;}remove(){this.element.remove();}
    },Map:class {
      constructor(options){this.options=options;this.center={lng:options.center[0],lat:options.center[1]};this.zoom=options.zoom;this.events={};this.sources={};this.layers=[];this.images={};this.moves=[];this.touchZoomRotate={disableRotation(){}};this.keyboard={disableRotation(){}};for(const name of ['dragPan','scrollZoom','boxZoom','doubleClickZoom','keyboard','touchZoomRotate'])this[name]={enable(){},disable(){},disableRotation(){}};this.canvas=document.createElement('canvas');document.getElementById(options.container).append(this.canvas);window.__maps.push(this);setTimeout(()=>{this.emit('style.load');this.emit('load');},20);}
      on(name,layer,fn){(this.events[typeof layer==='string'?name+':'+layer:name]??=[]).push(fn||layer);}
      emit(name,event){for(const fn of this.events[name]||[])fn(event);}
      getCenter(){return this.center;}getZoom(){return this.zoom;}getPitch(){return 0;}getBearing(){return 0;}getCanvas(){return this.canvas;}stop(){}
      easeTo(o){this.moves.push(o);if(o.center)this.center={lng:o.center[0],lat:o.center[1]};if(o.zoom)this.zoom=o.zoom;}
      jumpTo(o){this.easeTo(o);}flyTo(o){this.easeTo(o);}
      addControl(){}resize(){}setBearing(){}setFog(){}setLayoutProperty(){}setPaintProperty(){}setRenderWorldCopies(){}remove(){}
      getStyle(){return {sources:{},layers:[{id:'water',type:'fill','source-layer':'water'},{id:'road',type:'line'}]};}
      getBounds(){return {getWest:()=>-70,getEast:()=>20,getSouth:()=>-20,getNorth:()=>60};}
      getSource(id){return this.sources[id];}getLayer(id){return this.layers.find(l=>l.id===id);}hasImage(id){return !!this.images[id];}
      addSource(id,s){this.sources[id]={...s,setData(d){this.data=d;}};}
      addLayer(l){this.layers.push(l);}addImage(id,img){this.images[id]=img;}
      zoomIn(){this.zoom++;}zoomOut(){this.zoom--;}
    }};`}));
}
async function login(page) {
  await mapDouble(page);
  await page.goto('/admin/login');
  await page.locator('#email').fill('user1@nowave.test');
  await page.locator('#password').fill('test-password');
  await page.getByRole('button',{name:'Se connecter'}).click();
  await expect(page).toHaveURL(/\/admin$/);
}
async function filterReports(page,query) {
  const filters=page.locator('.map-view__filter-menu');
  if(await filters.getAttribute('open')===null)await filters.locator('summary').click();
  await page.locator('#map-report-search').fill(query);
  await expect(page.locator('.map-view__list')).toHaveAttribute('aria-busy','false');
}
test.beforeEach(async({page},info)=>{
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error'&&!message.text().startsWith('Failed to load resource'))errors.push(message.text());});
  const expected=info.title.startsWith('login validates')?[401,403]:info.title.startsWith('synthetic moderation')?[400,403,422]:info.title.startsWith('network failure')?[401,503]:[];
  page.on('response',response=>{if(response.status()>=400&&!expected.includes(response.status()))errors.push(`HTTP ${response.status()} ${new URL(response.url()).pathname}`);});
  page.on('requestfailed',request=>{const code=request.failure()?.errorText;if(code!=='net::ERR_ABORTED')errors.push(`Transport ${code} ${new URL(request.url()).pathname}`);});
  page.__testErrors=errors;
});
test.afterEach(async({page})=>{expect(page.__testErrors).toEqual([]);});

test('login validates identity, refuses non-admin and uses secure cookies',async({page,context})=>{
  await mapDouble(page);await page.goto('/admin');await expect(page).toHaveURL(/admin\/login/);
  await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('bad');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page.getByRole('alert')).toContainText('incorrect');
  await page.locator('#email').fill('user2@nowave.test');await page.locator('#password').fill('test-password');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page.getByRole('alert')).toContainText(/administration/);
  await page.locator('#email').fill('user1@nowave.test');await page.locator('#password').fill('test-password');await page.getByRole('button',{name:'Se connecter'}).click();await expect(page).toHaveURL(/\/admin$/);
  const cookie=(await context.cookies()).find(c=>c.name==='__Host-nowave_admin_session');expect(cookie).toMatchObject({httpOnly:true,secure:true,sameSite:'Strict',path:'/'});
});
test('rotation pauses on typing and respects reduced motion',async({page})=>{
  await mapDouble(page);await page.goto('/admin/login');await expect.poll(()=>page.evaluate(()=>window.__maps[0]?.moves.length)).toBeGreaterThan(0);
  await page.locator('#email').focus();const before=await page.evaluate(()=>window.__maps[0].moves.length);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__maps[0].moves.length)).toBe(before);
  await page.locator('#password-toggle').focus();await expect.poll(()=>page.evaluate(()=>window.__maps[0].moves.length)).toBeGreaterThan(before);
  await page.emulateMedia({reducedMotion:'reduce'});const stopped=await page.evaluate(()=>window.__maps[0].moves.length);await page.waitForTimeout(1200);expect(await page.evaluate(()=>window.__maps[0].moves.length)).toBe(stopped);
});
for(const [number,count] of [[2,0],[3,1],[4,49],[5,50],[6,51],[7,101]])test(`real SQL observation pagination exposes all ${count} reports with keyboard navigation`,async({page})=>{
  await login(page);await filterReports(page,`Synthetic report ${number}/`);
  const seen=[];
  for(let p=1;p<=Math.max(1,Math.ceil(count/50));p++){
    await expect(page.locator('.map-view__list')).toHaveAttribute('aria-busy','false');
    const buttons=page.locator('.map-view__list button');
    await expect(buttons).toHaveCount(Math.min(50,Math.max(0,count-(p-1)*50)));
    seen.push(...await buttons.allTextContents());
    if(count>p*50){const next=page.getByRole('button',{name:'Suivant',exact:true});await next.focus();await page.keyboard.press('Enter');await expect(page.locator('.map-view__page-number')).toHaveText(`Page ${p+1}`);}
  }
  expect(seen.length).toBe(count);expect(new Set(seen).size).toBe(count);
  if(count>50){await expect(page.getByRole('button',{name:'Suivant',exact:true})).toBeDisabled();await page.getByRole('button',{name:'Précédent',exact:true}).click();await expect(page.locator('.map-view__page-number')).toHaveText(`Page ${Math.ceil(count/50)-1}`);}
  if(count===0)await expect(page.locator('.map-view__result-status')).toContainText('Aucune observation');
  else {await page.locator('.map-view__list button').first().click();await expect(page.locator('.map-view__detail')).toContainText(`Synthetic report ${number}/`);await expect(page.getByRole('link',{name:'Fiche et historique'})).toBeVisible();}
});
test('users and moderation pages preserve pagination and contextual returns',async({page},info)=>{
  await login(page);await page.getByRole('link',{name:'Utilisateurs',exact:true}).click();
  await expect(page.locator('.users-table tbody tr')).toHaveCount(20);
  await page.getByRole('link',{name:'Page suivante'}).click();await expect(page.locator('.users-table tbody tr')).toHaveCount(8);
  await expect(page.locator('.page-total')).toHaveText('28');await expect(page).toHaveURL(/users\?page=2/);
  await page.screenshot({path:`test-results/${info.project.name}-users.png`});
  await page.getByRole('link',{name:'Modération',exact:true}).click();await expect(page).toHaveURL(/\/admin\/reports$/);
  await page.getByRole('link',{name:'Page suivante'}).click();const listUrl=page.url();
  await page.locator('.report-observation a').first().click();await expect(page.locator('.report-summary')).toContainText('Synthetic report');
  await page.getByRole('link',{name:'← Retour',exact:true}).click();await expect(page).toHaveURL(listUrl);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test('network failure retries and old responses cannot replace a new query',async({page,context})=>{
  await login(page);let release,started;const pending=new Promise(resolve=>release=resolve),requested=new Promise(resolve=>started=resolve);
  await page.route('**/api/v1/map/observations?*',async route=>{
    if(new URL(route.request().url()).searchParams.get('q')!=='slow')return route.continue();
    started();await pending;await route.fulfill({json:{items:[],has_more:false,next_cursor:null}}).catch(()=>{});
  });
  const filters=page.locator('.map-view__filter-menu');await filters.locator('summary').click();
  await page.locator('#map-report-search').fill('slow');await requested;
  await page.locator('#map-report-search').fill('Synthetic report 3/');await expect(page.locator('.map-view__list button')).toHaveCount(1);release();
  await expect(page.locator('.map-view__list')).toHaveAttribute('aria-busy','false');await expect(page.locator('.map-view__list')).toContainText('Synthetic report 3/0');
  await page.route('**/api/v1/map/observations?*',route=>route.fulfill({status:503,json:{detail:'fixture outage'}}),{times:1});
  await filterReports(page,'Synthetic report 5/');await expect(page.locator('.map-view__retry')).toBeVisible();await page.locator('.map-view__retry').click();await expect(page.locator('.map-view__list button')).toHaveCount(50);
  await context.clearCookies();await page.locator('.map-view__list button').first().click();await expect(page.locator('.map-view__admin-status')).toContainText('Session expirée');
});
test('shared map selection restores its view and keeps authorized photo links private',async({page},info)=>{
  await login(page);await expect(page.getByRole('button',{name:'Zoom avant',exact:true})).toBeEnabled();
  expect(await page.evaluate(()=>window.__maps[0].options)).toMatchObject({center:[-20,25],projection:'globe',dragRotate:false,maxPitch:0});
  await filterReports(page,'Synthetic report 5/');const before=await page.evaluate(()=>({center:window.__maps[0].getCenter(),zoom:window.__maps[0].getZoom()}));
  await page.locator('.map-view__list button').first().click();await expect(page.locator('.map-view__admin-status')).toHaveText('Actif');
  await page.getByRole('button',{name:'← Observations',exact:true}).click();
  await expect(page.locator('#map-report-search')).toHaveValue('Synthetic report 5/');
  expect(await page.evaluate(()=>({center:window.__maps[0].getCenter(),zoom:window.__maps[0].getZoom()}))).toEqual(before);
  await page.goto(`/admin?report=${id(5020)}`);await expect(page.locator('.map-view__detail')).toContainText('Synthetic report 5/20');await expect(page.getByRole('link',{name:'Masquer la photo',exact:true})).toBeVisible();
  const photo=page.getByRole('link',{name:'Ouvrir la photo',exact:true});await expect(photo).toBeVisible();await expect(photo).toHaveAttribute('href','/__fixtures/photo.svg');
  await expect.poll(()=>photo.locator('img').evaluate(img=>img.complete&&img.naturalWidth>0)).toBe(true);
  await page.getByRole('link',{name:'Fiche et historique'}).click();await expect(page.getByRole('link',{name:'Ouvrir la photo'})).toBeVisible();
  await page.goto(`/admin?report=${id(5020)}`);
  const visible=await(await page.request.get(`/admin/data/reports/${id(5020)}`)).json();expect(visible.photo.url).toBe('/__fixtures/photo.svg');
  await page.screenshot({path:`test-results/${info.project.name}-report.png`});
  await page.goto(`/admin?report=${id(5019)}`);await expect(page.locator('.map-view__detail')).toContainText('Synthetic report 5/19');await expect(page.getByRole('link',{name:'Masquer la photo',exact:true})).toHaveCount(0);
  const hidden=await(await page.request.get(`/admin/data/reports/${id(5019)}`)).json();expect(hidden.photo.url).toBeNull();
  await page.goto(`/admin?report=${id(5018)}`);await expect(page.locator('.map-view__detail')).toContainText('Synthetic report 5/18');await expect(page.getByRole('link',{name:'Masquer la photo',exact:true})).toHaveCount(0);
});
test('no Mapbox token keeps the map list, report and administration usable on mobile',async({page},info)=>{
  await page.route('**/api/v1/map/web-config',route=>route.fulfill({json:{mapbox_token:''}}));
  await login(page);await expect(page.locator('#navigation-status')).toContainText('La carte n’est pas disponible');
  await expect(page.locator('.map-view__list button')).toHaveCount(50);
  await page.goto(`/admin?report=${id(5018)}`);await expect(page.locator('.map-view__detail')).toContainText('Synthetic report 5/18');
  await page.getByRole('link',{name:'Utilisateurs',exact:true}).click();
  const header=await page.locator('.site-header').boundingBox(),title=await page.getByRole('heading',{name:'Utilisateurs',exact:true}).boundingBox();expect(title.y).toBeGreaterThanOrEqual(header.y+header.height);
  const count=await page.locator('.page-total').boundingBox();expect(count.x).toBeGreaterThan(title.x+title.width);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:`test-results/${info.project.name}-no-map.png`});
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

test('user search, status filters and user reports remain reachable',async({page})=>{
  await login(page);await page.getByRole('link',{name:'Utilisateurs',exact:true}).click();
  await page.getByLabel('Rechercher un compte').fill('user7@nowave.test');
  await page.getByRole('button',{name:'Rechercher',exact:true}).click();
  await expect(page.locator('.users-table tbody tr')).toHaveCount(1);
  await page.getByRole('link',{name:'Voir les signalements',exact:true}).click();
  await expect(page.locator('tbody tr')).toHaveCount(20);
  await page.getByRole('link',{name:'Page suivante',exact:true}).click();
  await expect(page.locator('tbody tr')).toHaveCount(20);
  await page.locator('tbody a').first().click();await expect(page.locator('.report-summary')).toContainText('Synthetic report 7/');
  await page.getByRole('link',{name:'← Retour',exact:true}).click();await expect(page).toHaveURL(url=>url.pathname===`/admin/users/${id(7)}/reports`&&url.searchParams.get("page")==="2");
  await page.getByRole('link',{name:'← Utilisateurs',exact:true}).click();await expect(page.getByLabel('Rechercher un compte')).toHaveValue('user7@nowave.test');
  await page.getByRole('button',{name:'Comptes suspendus',exact:true}).click();await expect(page.locator('main')).toContainText('Aucun utilisateur');
  await page.getByRole('button',{name:'Tous les statuts',exact:true}).click();await expect(page.locator('.users-table tbody tr')).toHaveCount(1);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
