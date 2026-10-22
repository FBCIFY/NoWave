"""Controlled Android before/after frames through the existing debug VM service."""
import asyncio,json,re,sys,time
from pathlib import Path
sys.path.insert(0,'/home/palms/NoWave/mobile/tool')
from nw220_device_validation import Device
from websockets.asyncio.client import connect

async def main(log,directory):
 out=Path(directory);out.mkdir(parents=True,exist_ok=True)
 base=re.search(r'(http://127.0.0.1:8181/[^\s]+)',Path(log).read_text())[1]
 async with connect(base.replace('http:','ws:')+'ws',max_size=64*1024*1024) as ws:
  d=Device(ws,None);vm=await d.rpc('getVM');d.isolate=next(i['id'] for i in vm['isolates'] if i['name']=='main')
  rows=[]
  async def save(name,settle=True):
   if settle:await d.settle()
   await asyncio.sleep(1)
   result=await d.marine();await d.capture(out/f'{name}.png')
   counts={}
   for feature in result['rendered']:
    for layer in feature['layers']:counts[layer]=counts.get(layer,0)+1
   row={'name':name,'camera':result['camera'],'rendered':counts,'features':{k:len(v) for k,v in result['data'].items()},'metrics':result['metrics']}
   rows.append(row);(out/'summary.json').write_text(json.dumps(rows,indent=2))
   print(json.dumps({k:v for k,v in row.items() if k!='metrics'}),flush=True)
  await d.camera(5.934167,43.085278,15.3,0,45);await save('after-saint-mandrier-z15.3')
  await d.camera(5.927,43.109,15.3,0,63.75);await save('after-photo-area-z15.3')
  for zoom in [12,13,14,15,16]:
   await d.camera(5.927,43.109,zoom,0,45);await save(f'after-toulon-z{zoom}')
  # Control the Z5 fallback threshold independently of provider data availability.
  for zoom in [4.99,5.0]:
   await d.camera(5.927,43.109,zoom,0,0);await save(f'after-threshold-z{zoom}',False)
  for zoom in [12,15.3,16]:
   await d.camera(5.365,43.295,zoom,0,45);await save(f'after-marseille-z{zoom}')
  start=time.monotonic()
  for i,zoom in enumerate([12,12.5,13,13.5,14,15,16,15,14,13,12]):
   await d.marine(action='camera',lon=5.927+i*.0003,lat=43.109,zoom=zoom,bearing=i*6,pitch=45)
   await asyncio.sleep(.1)
  await save('after-continuous-pan-zoom')
  rows[-1]['motion_duration_s']=round(time.monotonic()-start,3)
  await d.marine(action='reload');await asyncio.sleep(3);await save('after-style-reload')
  (out/'runtime-style.json').write_text(json.dumps(await d.marine(action='style'),indent=2))
  # An actual touch pan, then a settled snapshot. No report creation or account mutation.
  p=await asyncio.create_subprocess_exec('adb','-s','AV5PJV6328H03108','shell','input','swipe','400','700','300','850','500');await p.wait()
  await save('after-touch-pan')
  await d.camera(5.927,43.109,15.3,0,63.75);await save('after-final-photo-area')
  (out/'summary.json').write_text(json.dumps(rows,indent=2))
asyncio.run(main(*sys.argv[1:]))
