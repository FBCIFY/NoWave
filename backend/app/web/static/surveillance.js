(() => {
  const root = document.querySelector('.surveillance'); if (!root) return;
  const $ = id => document.getElementById(id);
  const status = $('map-status'); let map, mapAbort, detailAbort, userAbort, selected = null, userPage = 1, userPages = 1, users = [];
  const initial = [-30, 24], initialZoom = 2.4;
  const clean = value => String(value ?? '—');
  const emptyCollection = () => ({type:'FeatureCollection',features:[]});
  function markSelected(coordinates, category) {
    if (!map?.getSource('selected') || !coordinates) return;
    map.getSource('selected').setData({type:'FeatureCollection',features:[{
      type:'Feature',geometry:{type:'Point',coordinates},properties:{category},
    }]});
  }
  function el(tag, value) { const n = document.createElement(tag); n.textContent = clean(value); return n; }
  function field(dl, name, value) { dl.append(el('dt', name), el('dd', value)); }
  function openUsers(open) { $('users-panel').hidden = !open; const url = new URL(location); if (open) url.searchParams.set('panel','users'); else url.searchParams.delete('panel'); history.replaceState({},'',url); if(open) loadUsers(); map?.resize(); }
  $('users-open').onclick = $('users-tab').onclick = () => openUsers(true);
  $('users-close').onclick = () => openUsers(false);
  $('report-close').onclick = () => { $('report-panel').hidden = true; selected = null; detailAbort?.abort(); const url = new URL(location); url.searchParams.delete('report'); history.replaceState({},'',url); map?.getSource('selected')?.setData(emptyCollection()); map?.resize(); };
  function reportLink(id, action, label, parent) { const a=el('a',label); a.href=`/admin/actions/reports/${encodeURIComponent(id)}/${action}`; parent.append(a); }
  async function selectReport(id, coordinates, category) {
    selected = id; detailAbort?.abort(); detailAbort = new AbortController();
    $('report-panel').hidden = false; $('report-detail').replaceChildren(el('p','Chargement…'));
    const url = new URL(location); url.searchParams.set('report',id); history.replaceState({},'',url);
    if (coordinates && map) map.easeTo({center:coordinates,zoom:Math.max(map.getZoom(),7),duration:matchMedia('(prefers-reduced-motion: reduce)').matches?0:900});
    markSelected(coordinates, category); map?.resize();
    try {
      const response = await fetch(`/admin/data/reports/${encodeURIComponent(id)}`,{signal:detailAbort.signal,credentials:'same-origin'});
      if(response.redirected && response.url.includes('/admin/login')) throw Error('Session expirée. Reconnectez-vous.');
      if(!response.ok) throw Error(`Fiche indisponible (${response.status}).`);
      const data=await response.json(); if(selected!==id) return;
      markSelected(data.final_position?.coordinates, data.category);
      if (!coordinates && map && data.final_position?.coordinates) map.easeTo({center:data.final_position.coordinates,zoom:7,duration:matchMedia('(prefers-reduced-motion: reduce)').matches?0:900});
      const box=$('report-detail'), dl=document.createElement('dl'); dl.className='detail-grid';
      field(dl,'Identifiant',data.id); field(dl,'Catégorie',data.category); field(dl,'Statut',data.status);
      field(dl,'Observation',data.observed_at); field(dl,'Expiration',data.expires_at); field(dl,'Retrait',data.removed_at);
      field(dl,'Latitude',data.final_position.coordinates[1]); field(dl,'Longitude',data.final_position.coordinates[0]);
      field(dl,'Positionnement',data.positioning_mode); field(dl,'Auteur',data.author?.deleted?'Compte supprimé':data.author?.username);
      field(dl,'Auteur ID',data.author?.id); field(dl,'E-mail',data.author?.email); field(dl,'Compte',data.author?.status);
      field(dl,'Bateau',data.boat?.name); field(dl,'Description',data.description || 'Aucune description'); box.replaceChildren(dl);
      if(data.photo?.hidden_at) box.append(el('p','Photo masquée'));
      else if(data.photo?.url) { const a=document.createElement('a'), img=document.createElement('img'); a.href=data.photo.url; a.target='_blank'; a.rel='noopener noreferrer'; img.src=data.photo.url; img.alt='Photographie du signalement'; img.className='photo'; img.onerror=()=>img.replaceWith(el('p','Photo indisponible')); a.append(img); box.append(a); }
      else box.append(el('p','Aucune photo'));
      const actions=document.createElement('div'); actions.className='detail-actions';
      if(data.status==='removed') reportLink(id,'restore','Restaurer',actions);
      else if(data.status==='active') reportLink(id,'remove','Retirer',actions);
      if(data.photo?.url) reportLink(id,'hide-photo','Masquer la photo',actions);
      box.append(actions);
    } catch(error) { if(error.name!=='AbortError' && selected===id) $('report-detail').replaceChildren(el('p',error.message)); }
  }
  function renderUsers() {
    const q=$('user-search').value.trim().toLocaleLowerCase(); const list=$('users-list'); list.replaceChildren();
    for(const user of users.filter(u=>`${u.username} ${u.id} ${u.email}`.toLocaleLowerCase().includes(q))) {
      const b=el('button',`${user.username} · ${user.status}`); b.type='button'; b.className='user-row'; b.append(el('small',`${user.role} · ${user.reports_count} signalement(s)`)); b.onclick=()=>{
        const box=$('user-detail'), dl=document.createElement('dl'); dl.className='detail-grid';
        for(const [name,value] of Object.entries({ID:user.id,E_mail:user.email,Rôle:user.role,Statut:user.status,Création:user.created_at,Signalements:user.reports_count})) field(dl,name.replace('_','-'),value);
        box.replaceChildren(el('h3',user.username),dl); const links=document.createElement('div'); links.className='detail-actions';
        const reports=el('button','Afficher les signalements'); reports.type='button'; reports.onclick=async()=>{
          const old=box.querySelector('.user-reports'); old?.remove(); const section=document.createElement('div');section.className='user-reports';section.append(el('p','Chargement…'));box.append(section);
          try{const response=await fetch(`/admin/data/users/${encodeURIComponent(user.id)}/reports`,{credentials:'same-origin'});if(!response.ok)throw Error(`Liste indisponible (${response.status}).`);const data=await response.json();section.replaceChildren();for(const item of data.items){const a=el('a',`${item.category} · ${item.status} · ${item.observed_at}`);a.href=`/admin?report=${encodeURIComponent(item.id)}`;a.style.display='block';section.append(a);}if(!data.items.length)section.append(el('p','Aucun signalement.'));}catch(error){section.replaceChildren(el('p',error.message));}
        }; links.append(reports);
        const action=user.status==='suspended'?'reactivate':'suspend'; const mod=el('a',action==='suspend'?'Suspendre':'Réactiver'); mod.href=`/admin/actions/users/${encodeURIComponent(user.id)}/${action}`; links.append(mod); box.append(links);
      }; list.append(b);
    }
    if(!list.childElementCount) list.append(el('p','Aucun utilisateur sur cette page.'));
  }
  async function loadUsers() {
    userAbort?.abort(); userAbort=new AbortController(); $('users-list').replaceChildren(el('p','Chargement…'));
    try { const url=new URL('/admin/data/users',location); url.searchParams.set('page',userPage); if($('user-status').value) url.searchParams.set('status',$('user-status').value);if($('user-search').value.trim())url.searchParams.set('search',$('user-search').value.trim());
      const response=await fetch(url,{signal:userAbort.signal,credentials:'same-origin'}); if(response.redirected&&response.url.includes('/admin/login')) throw Error('Session expirée. Reconnectez-vous.'); if(!response.ok) throw Error(`Liste indisponible (${response.status}).`);
      const data=await response.json(); users=data.items; userPages=data.pages; $('users-count').textContent=`${data.total} utilisateurs`; $('users-page').textContent=`${userPage} / ${Math.max(userPages,1)}`; $('users-prev').disabled=userPage<=1; $('users-next').disabled=userPage>=userPages; renderUsers();
    } catch(error) { if(error.name!=='AbortError') $('users-list').replaceChildren(el('p',error.message)); }
  }
  let searchTimer; $('user-search').oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{userPage=1;loadUsers();},250);}; $('user-status').onchange=()=>{userPage=1;loadUsers();}; $('users-prev').onclick=()=>{if(userPage>1){userPage--;loadUsers();}}; $('users-next').onclick=()=>{if(userPage<userPages){userPage++;loadUsers();}};
  if(new URL(location).searchParams.get('panel')==='users') openUsers(true);
  if(!root.dataset.token || !window.mapboxgl || !mapboxgl.supported()) {status.textContent='Carte indisponible : configurez MAPBOX_PUBLIC_TOKEN. Les listes et actions restent accessibles.'; return;}
  mapboxgl.accessToken=root.dataset.token;
  try {map=new mapboxgl.Map({container:'surveillance-map',style:'mapbox://styles/mapbox/dark-v11',projection:'mercator',renderWorldCopies:false,maxBounds:[[-180,-85],[180,85]],center:initial,zoom:initialZoom,minZoom:0.5,maxZoom:12,pitch:0,bearing:0,dragRotate:false,pitchWithRotate:false,touchPitch:false,maxPitch:0,attributionControl:true});
    map.touchZoomRotate.disableRotation(); map.on('rotate',()=>map.setBearing(0));
    map.on('style.load',()=>window.NoWaveMaritimeStyle.apply(map));
    map.on('load',()=>{map.addSource('reports',{type:'geojson',data:{type:'FeatureCollection',features:[]},cluster:true,clusterRadius:48,clusterMaxZoom:11});
      map.addSource('selected',{type:'geojson',data:emptyCollection()});
      map.addLayer({id:'cluster-halo',type:'circle',source:'reports',filter:['has','point_count'],paint:{'circle-color':'#e64255','circle-radius':['step',['get','point_count'],25,10,30,50,36],'circle-opacity':0.18,'circle-blur':0.65}});
      map.addLayer({id:'cluster-shadow',type:'circle',source:'reports',filter:['has','point_count'],paint:{'circle-color':'#020711','circle-radius':['step',['get','point_count'],21,10,27,50,33],'circle-opacity':0.55,'circle-blur':0.4,'circle-translate':[0,2]}});
      map.addLayer({id:'clusters',type:'circle',source:'reports',filter:['has','point_count'],paint:{'circle-color':'#cf3149','circle-radius':['step',['get','point_count'],18,10,24,50,30],'circle-opacity':0.97,'circle-stroke-color':'#ffd4db','circle-stroke-width':0.9}});
      map.addLayer({id:'cluster-count',type:'symbol',source:'reports',filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':13},paint:{'text-color':'#fff'}});
      map.addLayer({id:'point-halo',type:'circle',source:'reports',filter:['!', ['has','point_count']],paint:{'circle-color':'#e64255','circle-radius':['interpolate',['linear'],['zoom'],1,14,6,20,12,25],'circle-opacity':0.16,'circle-blur':0.7,'circle-translate':[0,0]}});
      const iconsReady = window.NoWaveMarkerIcons.install(map);
      if (iconsReady) {
        map.addLayer({id:'points',type:'symbol',source:'reports',filter:['!', ['has','point_count']],layout:{'icon-image':['concat','report-',['get','category']],'icon-size':['interpolate',['linear'],['zoom'],1,0.75,6,0.95,12,1.15],'icon-anchor':'center','icon-allow-overlap':true,'icon-ignore-placement':true}});
      } else {
        map.addLayer({id:'points',type:'circle',source:'reports',filter:['!', ['has','point_count']],paint:{'circle-color':'#e64255','circle-radius':8,'circle-stroke-color':'#fff','circle-stroke-width':1}});
      }
      map.addLayer({id:'selected-report',type:'circle',source:'selected',paint:{'circle-color':'#e64255','circle-radius':19,'circle-opacity':0.15,'circle-stroke-color':'#f5faff','circle-stroke-opacity':0.85,'circle-stroke-width':1.5,'circle-blur':0.25,'circle-translate':[0,0]}});
      if (iconsReady) map.addLayer({id:'selected-icon',type:'symbol',source:'selected',layout:{'icon-image':['concat','report-',['get','category']],'icon-size':1.2,'icon-anchor':'center','icon-allow-overlap':true,'icon-ignore-placement':true}});
      map.on('click','clusters',e=>window.NoWaveClusterInteraction.expand(map,e.features[0],matchMedia('(prefers-reduced-motion: reduce)').matches));
      map.on('click','points',e=>selectReport(e.features[0].properties.id,e.features[0].geometry.coordinates,e.features[0].properties.category));
      map.on('moveend',loadReports); loadReports(); const direct=new URL(location).searchParams.get('report'); if(direct&&/^[0-9a-f-]{36}$/i.test(direct)) selectReport(direct);
    });
    map.on('error',()=>{status.textContent='Cartographie momentanément indisponible. Les listes restent accessibles.';});
  } catch(_) {status.textContent='Carte indisponible. Les listes restent accessibles.';}
  async function loadReports(){mapAbort?.abort(); mapAbort=new AbortController(); const bounds=map.getBounds(); const west=Math.max(-180,bounds.getWest()),east=Math.min(180,bounds.getEast()); if(west>=east)return;
    const url=new URL('/admin/data/reports',location); for(const [key,value] of Object.entries({west,south:Math.max(-90,bounds.getSouth()),east,north:Math.min(90,bounds.getNorth())}))url.searchParams.set(key,value);
    status.textContent='Chargement des signalements…'; try{const response=await fetch(url,{signal:mapAbort.signal,credentials:'same-origin'});if(response.redirected&&response.url.includes('/admin/login'))throw Error('Session expirée. Reconnectez-vous.');if(!response.ok)throw Error(`Signalements indisponibles (${response.status}).`);const data=await response.json();map.getSource('reports').setData(data);status.textContent=data.truncated?'Zone dense : zoomez pour afficher tous les signalements.':`${data.features.length} signalements dans la zone visible`;}
    catch(error){if(error.name!=='AbortError')status.textContent=error.message;}
  }
  $('zoom-in').onclick=()=>map?.zoomIn(); $('zoom-out').onclick=()=>map?.zoomOut(); $('reset-map').onclick=()=>map?.easeTo({center:initial,zoom:initialZoom,bearing:0,pitch:0,duration:600});
})();
