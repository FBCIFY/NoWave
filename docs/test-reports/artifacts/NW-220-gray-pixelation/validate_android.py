"""Real main.dart / Mapbox Android validation against the local marine backend."""
import asyncio,json,re,sys,time
from pathlib import Path
sys.path.insert(0,'/home/palms/NoWave/mobile/tool')
from nw220_device_validation import Device
from websockets.asyncio.client import connect
async def adb(*args):
 p=await asyncio.create_subprocess_exec('adb','-s','AV5PJV6328H03108',*args,stdout=asyncio.subprocess.PIPE)
 out,_=await p.communicate();return out
async def main():
 out=Path('/tmp/nowave-gray-extended-v7');out.mkdir(exist_ok=True)
 await asyncio.sleep(3)
 log=Path('/tmp/nowave-gray-v7-android.log').read_text();base=re.search(r'(http://127.0.0.1:8181/[^\s]+)',log)[1]
 async with connect(base.replace('http:','ws:')+'ws',max_size=64*1024*1024) as ws:
  d=Device(ws,None);vm=await d.rpc('getVM');d.isolate=next(i['id'] for i in vm['isolates'] if i['name']=='main');rows=[]
  async def save(name,settle=True):
   if settle:await d.settle()
   await asyncio.sleep(.7);r=await d.marine();await d.capture(out/(name+'.png'))
   counts={}
   for feature in r['rendered']:
    for layer in feature['layers']:counts[layer]=counts.get(layer,0)+1
   row={'name':name,'camera':r['camera'],'rendered':counts,'features':{k:len(v) for k,v in r['data'].items()},'contour_ids':sorted(str(f['id']) for f in r['data']['depth-contours']),'metrics':r['metrics']}
   rows.append(row);(out/'summary.json').write_text(json.dumps(rows,indent=2));print(json.dumps({k:v for k,v in row.items() if k not in ['metrics','contour_ids']}),flush=True)
  for zoom in [13,14,15,16,16.3]:
   await d.camera(5.934167,43.085278,zoom,315,45);await save(f'gray-z{zoom}')
  for zoom in [12,13,13.8,14,15,16]:
   await d.camera(5.915,43.105,zoom,0,63.75);await save(f'pixels-z{zoom}')
  for name,lon,lat,zoom,pitch in [
   ('historic-coast',5.927,43.109,15.3,63.75),
   ('marseille',5.365,43.295,13.8,45),
   ('marseille-detail',5.365,43.295,16.3,45),
   ('natural-coast',6.205,43.0,14,45),
   ('open-water',5.94,43.064,16.3,45),
   ('offshore-13',5.9293,43.0637,13,45),
   ('offshore-16',5.9293,43.0637,16,45),
   ('offshore-return',5.9293,43.0637,13,45),
  ]:
   await d.camera(lon,lat,zoom,0,pitch);await save(name)
  await adb('shell','dumpsys','gfxinfo','fr.blueway.app','reset')
  start=time.monotonic()
  for i,z in enumerate([12,12.5,13,13.8,14,15,16,16.3,15,14,13]):
   await d.marine(action='camera',lon=5.915+i*.0002,lat=43.105,zoom=z,bearing=i*6,pitch=45);await asyncio.sleep(.1)
  await save('continuous-pan-zoom');rows[-1]['duration_s']=round(time.monotonic()-start,3)
  await adb('shell','input','swipe','420','700','300','850','600');await save('touch-pan')
  await d.marine(action='reload');await asyncio.sleep(3);await save('reload')
  (out/'style.json').write_text(json.dumps(await d.marine(action='style'),indent=2))
  await d.camera(5.934167,43.085278,16.3,315,45);await save('final-gray')
  await adb('shell','input','tap','52','1535');await asyncio.sleep(2);await d.capture(out/'attribution.png');await adb('shell','input','keyevent','KEYCODE_BACK')
  (out/'meminfo.txt').write_bytes(await adb('shell','dumpsys','meminfo','fr.blueway.app'))
  (out/'gfxinfo.txt').write_bytes(await adb('shell','dumpsys','gfxinfo','fr.blueway.app'))
  (out/'summary.json').write_text(json.dumps(rows,indent=2))
asyncio.run(main())
