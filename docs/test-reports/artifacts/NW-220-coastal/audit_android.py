import asyncio,json,re,sys
from pathlib import Path
sys.path.insert(0,'/home/palms/NoWave/mobile/tool')
from nw220_device_validation import Device
from websockets.asyncio.client import connect
OUT=Path('/tmp/nowave-coastal-device');OUT.mkdir(exist_ok=True)
async def main(mode):
 log=Path('/tmp/nowave-coastal-android.log').read_text()
 base=re.search(r'(http://127.0.0.1:8181/[^\s]+)',log)[1]
 async with connect(base.replace('http:','ws:')+'ws',max_size=64*1024*1024) as ws:
  d=Device(ws,None);vm=await d.rpc('getVM');d.isolate=next(i['id'] for i in vm['isolates'] if i['name']=='main')
  info=await d.rpc('getIsolate',{'isolateId':d.isolate});lib=next(l['id'] for l in info['libraries'] if l['uri'].endswith('/marine_debug.dart'))
  async def evaluate(expr):
   r=await d.rpc('evaluate',{'isolateId':d.isolate,'targetId':lib,'expression':expr})
   if r.get('type') in ['Error','@Error']:raise RuntimeError(r)
   return r
  async def prop(layer,key,value):
   return await evaluate(f'MarineDebug._map!.style.setStyleLayerProperty({json.dumps(layer)}, {json.dumps(key)}, {json.dumps(value)})')
  async def save(name):
   await asyncio.sleep(1)
   r=await d.marine();(OUT/f'{name}.json').write_text(json.dumps(r,indent=2));await d.capture(OUT/f'{name}.png');print(name,r['camera'],flush=True)
  if mode=='baseline':
   (OUT/'initial.json').write_text(json.dumps(await d.marine(),indent=2))
   await d.camera(5.934167,43.085278,15.3,0,45);await d.settle();await save('before-normal')
   await prop('nowave-bathymetry-raster','visibility','none');await save('before-no-raster')
   await prop('nowave-bathymetry-raster','visibility','visible')
   for layer in ['nowave-port-docks','nowave-port-pier-polygons','nowave-port-breakwaters','nowave-port-groynes','nowave-port-piers','nowave-land-relief']:
    await prop(layer,'visibility','none')
   await save('before-no-docks-relief')
   await d.marine(action='reload');await asyncio.sleep(3);await d.settle();await save('before-restored')
   (OUT/'before-style.json').write_text(json.dumps(await d.marine(action='style'),indent=2))
  elif mode=='fallback-probe':
   await evaluate('MarineDebug._map!.style.setStyleImportConfigProperty("basemap", "colorWater", "#93ACB0")')
   await prop('nowave-earth-ocean','fill-color','#93ACB0');await save('probe-neutral-fallback')
   await d.marine(action='reload');await asyncio.sleep(2);await d.settle()
  elif mode=='query':
   print(json.dumps(await d.marine(),indent=2))
  elif mode=='evaluate':
   print(json.dumps(await evaluate(sys.argv[2]),indent=2))
asyncio.run(main(sys.argv[1]))
