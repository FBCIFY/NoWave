const assert=require('node:assert/strict');
const {test}=require('node:test');
const {harness,response,flush}=require('./support/surveillance-harness.cjs');
const user=id=>({id,username:id,email:`${id}@test`,status:'active',reports_count:41});
const items=(n,start=1)=>Array.from({length:n},(_,i)=>({id:`r${start+i}`,category:'pollution',status:'active',observed_at:'2026-10-23'}));
async function open(h) {h.ids['users-open'].click();h.pending.at(-1).resolve(response({items:[user('alice'),user('bob')],pages:1,total:2}));await flush();h.ids['users-list'].children[0].click();h.ids['user-detail'].all('button')[0].click();}
const section=h=>h.ids['user-detail'].all('section')[0];
const button=(h,text)=>section(h).all('button').find(b=>b.text===text);
for(const count of [0,1,20,21,40,41]) test(`user can reach every report link for ${count} reports`,async()=>{
  const h=harness();await open(h);let seen=[];
  for(let page=1;page<=Math.max(1,Math.ceil(count/20));page++) {
    assert.equal(button(h,'Page suivante').disabled,true);
    const size=Math.max(0,Math.min(20,count-(page-1)*20));
    h.pending.at(-1).resolve(response({items:items(size,(page-1)*20+1),page,has_more:count>page*20}));await flush();
    const links=section(h).all('a'); seen.push(...links.map(a=>a.href));
    assert.equal(button(h,'Page précédente').disabled,page===1);
    assert.equal(button(h,'Page suivante').disabled,count<=page*20);
    if(count>page*20)button(h,'Page suivante').click();
  }
  assert.equal(seen.length,count);if(count>=21)assert.ok(seen.includes('/admin?report=r21'));
  assert.match(section(h).text,count?/Fin de la liste/:/Aucun signalement/);
});
test('late user responses cannot mix results',async()=>{
  const h=harness();await open(h);const old=h.pending.at(-1);
  h.ids['users-list'].children[1].click();h.ids['user-detail'].all('button')[0].click();
  const bob=h.pending.at(-1);bob.resolve(response({items:items(1,80),has_more:false}));await flush();
  old.resolve(response({items:items(20),has_more:true}));await flush();
  assert.deepEqual(section(h).all('a').map(a=>a.href),['/admin?report=r80']);assert.equal(old.options.signal.aborted,true);
});
test('page loading disables navigation; restarting ignores out-of-order response',async()=>{
  const h=harness();await open(h);h.pending.at(-1).resolve(response({items:items(20),has_more:true}));await flush();
  button(h,'Page suivante').click();const page2=h.pending.at(-1),before=h.pending.length;
  button(h,'Page suivante').click();button(h,'Page précédente').click();assert.equal(h.pending.length,before);
  h.ids['user-detail'].all('button')[0].click();h.pending.at(-1).resolve(response({items:items(1,90),has_more:false}));await flush();
  page2.resolve(response({items:items(20,21),has_more:true}));await flush();assert.equal(section(h).all('a')[0].href,'/admin?report=r90');
});
for(const failure of ['network','http','expired','401','403'])test(`report pagination handles ${failure} and can retry`,async()=>{
  const h=harness();await open(h);const request=h.pending.at(-1);
  if(failure==='network')request.reject(Error('Network unavailable'));
  else request.resolve(response(null,failure==='expired'?{redirected:true,url:'https://local.test/admin/login'}:{ok:false,status:failure==='http'?503:Number(failure)}));
  await flush();assert.match(section(h).text,/Network|503|Session expirée/);button(h,'Réessayer').click();
  h.pending.at(-1).resolve(response({items:[],has_more:false}));await flush();assert.match(section(h).text,/Aucun signalement/);
});
test('nonexistent page can go back and closing aborts then resets the detail',async()=>{
  const h=harness();await open(h);h.pending.at(-1).resolve(response({items:items(20),has_more:true}));await flush();
  button(h,'Page suivante').click();h.pending.at(-1).resolve(response({items:[],has_more:false}));await flush();
  assert.match(section(h).text,/Aucun signalement sur cette page/);button(h,'Page précédente').click();const old=h.pending.at(-1);
  h.ids['users-close'].click();assert.equal(old.options.signal.aborted,true);old.resolve(response({items:items(1),has_more:false}));await flush();
  assert.equal(h.ids['user-detail'].childElementCount,0);h.ids['users-open'].click();assert.equal(section(h),undefined);
});
test('latest user list wins even when abort is ignored by transport',async()=>{
  const h=harness();h.ids['users-open'].click();const old=h.pending.at(-1);h.ids['user-status'].onchange();
  h.pending.at(-1).resolve(response({items:[user('bob')],pages:1,total:1}));await flush();old.resolve(response({items:[user('alice')],pages:1,total:1}));await flush();assert.match(h.ids['users-list'].text,/bob/);assert.doesNotMatch(h.ids['users-list'].text,/alice/);
});
for(const icons of [true,false])test(`Mapbox layers keep selection above red clusters and ${icons?'sprite':'circle'} fallback`,async()=>{
  const h=harness({withMap:true,icons});h.handlers['load:']();
  const layer=id=>h.layers.find(x=>x.id===id);
  assert.equal(layer('clusters').paint['circle-color'],'#cf3149');
  assert.ok(h.layers.indexOf(layer('selected-report'))>h.layers.indexOf(layer('clusters')));
  if(icons){assert.equal(layer('points').layout['icon-anchor'],'center');assert.match(JSON.stringify(layer('points').layout['icon-image']),/coalesce.*report-unknown/);assert.equal(layer('selected-icon').layout['icon-allow-overlap'],true);}
  else assert.equal(layer('points').type,'circle');
  h.pending.at(-1).resolve(response({features:items(1000),truncated:true}));await flush();assert.match(h.ids['map-status'].text,/Affichage partiel.*uniquement/);assert.doesNotMatch(h.ids['map-status'].text,/zoomez/);
  h.handlers['moveend:']();const old=h.pending.at(-1);h.handlers['moveend:']();h.pending.at(-1).resolve(response({features:[],truncated:false}));await flush();old.resolve(response({features:items(1000),truncated:true}));await flush();assert.equal(h.sources.reports.data.features.length,0);
});

test('direct report works before map load and stale same-id response cannot overwrite after reopening',async()=>{
  const id='11111111-1111-1111-1111-111111111111';
  const h=harness({withMap:true,href:`https://local.test/admin?report=${id}`});const old=h.pending.at(-1);
  assert.match(old.url,/data\/reports\//);h.handlers['load:']();h.ids['report-close'].click();
  h.handlers['click:points']({features:[{properties:{id,category:'pollution'},geometry:{coordinates:[-30,24]}}]});
  const data={id,category:'pollution',status:'active',final_position:{coordinates:[-30,24]},description:'fresh'};
  h.pending.at(-1).resolve(response(data));await flush();
  old.resolve(response({...data,description:'obsolete'}));await flush();assert.equal(h.ids['report-panel'].hidden,false);
  assert.match(h.ids['report-detail'].text,/fresh/);assert.doesNotMatch(h.ids['report-detail'].text,/obsolete/);
});
