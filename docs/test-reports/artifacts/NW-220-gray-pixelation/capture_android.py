import asyncio,json,re,sys
from pathlib import Path
sys.path.insert(0,'/home/palms/NoWave/mobile/tool')
from nw220_device_validation import Device
from websockets.asyncio.client import connect
async def main(log,directory,mode):
 out=Path(directory);out.mkdir(parents=True,exist_ok=True)
 base=re.search(r'(http://127.0.0.1:8181/[^\s]+)',Path(log).read_text())[1]
 async with connect(base.replace('http:','ws:')+'ws',max_size=64*1024*1024) as ws:
  d=Device(ws,None);vm=await d.rpc('getVM');d.isolate=next(i['id'] for i in vm['isolates'] if i['name']=='main');rows=[]
  async def save(name):
   await d.settle();await asyncio.sleep(1);r=await d.marine();await d.capture(out/f'{name}.png')
   row={k:v for k,v in r.items() if k not in ['data','rendered']};row['name']=name;row['counts']={k:len(v) for k,v in r['data'].items()};rows.append(row);(out/'summary.json').write_text(json.dumps(rows,indent=2));print(name,row['camera'],flush=True)
  if mode=='baseline':
   await d.camera(5.934167,43.085278,16.3,315,45);await save('baseline-gray')
   await d.camera(5.915,43.105,13.8,0,63.75);await save('baseline-pixels')
   (out/'style.json').write_text(json.dumps(await d.marine(action='style'),indent=2))
asyncio.run(main(*sys.argv[1:]))
