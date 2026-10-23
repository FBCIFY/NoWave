const fs = require('node:fs');
const vm = require('node:vm');
class Element {
  constructor(tag='div') { this.tagName=tag; this.children=[]; this.dataset={}; this.style={}; this.value=''; this.hidden=false; this.disabled=false; this.textContent=''; this.attributes={}; }
  append(...children) { for(const c of children) { c.parent=this; this.children.push(c); } }
  replaceChildren(...children) { this.children=[]; this.textContent=''; this.append(...children); }
  setAttribute(k,v) { this.attributes[k]=v; }
  contains(node) { return this===node || this.children.some(c=>c.contains(node)); }
  focus() {}
  get childElementCount() { return this.children.length; }
  remove() { if(this.parent) this.parent.children=this.parent.children.filter(x=>x!==this); }
  click() { if(!this.disabled) return this.onclick?.(); }
  get text() { return this.textContent + this.children.map(x=>x.text).join(' '); }
  all(tag) { return this.children.flatMap(x=>[...(x.tagName===tag?[x]:[]),...x.all(tag)]); }
}
function deferred() { let resolve,reject; const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject}; }
function response(data, extra={}) { return {ok:true,status:200,redirected:false,json:async()=>data,...extra}; }
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function harness({withMap=false,icons=true,href='https://local.test/admin'}={}) {
  const ids={}; for(const id of ['map-status','users-panel','users-open','users-tab','users-close','report-close','report-panel','report-detail','user-detail','users-list','user-search','user-status','users-count','users-page','users-prev','users-next','zoom-in','zoom-out','reset-map']) ids[id]=new Element();
  const root=new Element();root.dataset.token=withMap?'public-test':'';
  const pending=[],layers=[],images=[],sources={},handlers={};
  const map={on(event,layer,fn) { handlers[layer?`${event}:${typeof layer==='string'?layer:''}`:event]=fn||layer; },
    resize(){},getSource:id=>sources[id],addSource(id,s){sources[id]={...s,setData(data){this.data=data;}};},
    addLayer(l){layers.push(l);},touchZoomRotate:{disableRotation(){}},getZoom:()=>3,easeTo(){},
    getBounds:()=>({getWest:()=>-70,getEast:()=>20,getSouth:()=>-20,getNorth:()=>60})};
  const context={window:{NoWaveMaritimeStyle:{apply(){}},NoWaveMarkerIcons:{install(){return icons;}},NoWaveClusterInteraction:{expand(){}}},
    document:{querySelector:()=>root,getElementById:id=>ids[id],createElement:tag=>new Element(tag)},
    location:new URL(href),history:{replaceState(){}},URL,AbortController,matchMedia:()=>({matches:false}),setTimeout,clearTimeout,
    fetch:(url,options)=>{const d=deferred();pending.push({url:String(url),options,...d});return d.promise;}};
  if(withMap) context.mapboxgl=context.window.mapboxgl={supported:()=>true,Map:function(){return map;}};
  vm.runInNewContext(fs.readFileSync('backend/app/web/static/surveillance.js','utf8'),context);
  return {ids,pending,layers,images,sources,handlers,map};
}
module.exports={harness,response,flush};
