import sys,asyncio,json,re
from pathlib import Path
sys.path.insert(0,'/home/palms/NoWave/mobile/tool')
from nw220_device_validation import Device
from websockets.asyncio.client import connect
async def main():
 out=Path('/tmp/nowave-coastal-after');base=re.search(r'(http://127.0.0.1:8181/[^\s]+)',Path('/tmp/nowave-coastal-android-after.log').read_text())[1]
 async with connect(base.replace('http:','ws:')+'ws',max_size=64*1024*1024) as ws:
  d=Device(ws,None);vm=await d.rpc('getVM');d.isolate=next(i['id'] for i in vm['isolates'] if i['name']=='main');rows=[]
  for n,z in enumerate([13,14,16,13]):
   await d.camera(5.9293,43.0637,z,0,45);await d.settle();r=await d.marine()
   counts={}
   for f in r['rendered']:
    for layer in f['layers']:counts[layer]=counts.get(layer,0)+1
   row={'zoom':z,'rendered':counts,'contour_ids':sorted(str(f['id']) for f in r['data']['depth-contours']),'errors':r['metrics']['errors'],'active':r['metrics']['active']};rows.append(row)
   await d.capture(out/f'after-offshore-{n}-z{z}.png');print(json.dumps(row),flush=True)
   (out/'contours.json').write_text(json.dumps(rows,indent=2))
  await d.camera(5.927,43.109,15.3,0,63.75);await d.settle()
asyncio.run(main())
