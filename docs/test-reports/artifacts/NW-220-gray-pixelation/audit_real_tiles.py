"""Reproducible, bounded real-data audit; never contacts a business API."""
import asyncio,base64,json,time
from io import BytesIO
from pathlib import Path
import numpy as np
from PIL import Image
from app.infrastructure.adapters import emodnet_bathymetry as b
from app.infrastructure.marine.runtime import get_coastline_mask,close_marine_service
from app.infrastructure.marine.visual_water import render_visual_water,PADDING
out=Path('/tmp/nowave-gray-real-v7');out.mkdir(exist_ok=True)
async def main():
 rows=[];coast=get_coastline_mask()
 for z,x,y in [(12,2115,1503),(13,4231,3007),(14,8461,6012),(14,8462,6012),(14,8461,6013),(14,8462,6013),(14,8461,6014),(14,8462,6014),(14,8461,6015),(14,8462,6015)]:
  name=f'{z}-{x}-{y}';folder=out/name;folder.mkdir(exist_ok=True);calls=[]
  original=b._request_tile
  def request(params):
   t=time.perf_counter();response=original(params);calls.append({'params':params,'seconds':time.perf_counter()-t,'bytes':len(response.content)});(folder/'source.png').write_bytes(response.content);return response
  b._request_tile=request;t=time.perf_counter()
  try:
   raw=await asyncio.to_thread(b.fetch_bathymetry_tile,z,x,y,True)
   assert await asyncio.to_thread(b.fetch_bathymetry_tile,z,x,y,True)==raw
  finally:b._request_tile=original
  generated=time.perf_counter()-t;(folder/'recolored-context.png').write_bytes(raw)
  from app.domain.marine_tile import Tile
  water=await coast.get_context(Tile(z,x,y),raw);water.save(folder/'water-context.png')
  t=time.perf_counter();final=await asyncio.to_thread(render_visual_water,raw,water);processed=time.perf_counter()-t;(folder/'final.png').write_bytes(final)
  im=Image.open(BytesIO(final));src=np.array(Image.open(BytesIO(raw)).convert('RGBA'))[PADDING:-PADDING,PADDING:-PADDING];mask=np.array(water)[PADDING:-PADDING,PADDING:-PADDING];dst=np.array(im)
  alpha=(src[:,:,3].astype(np.uint16)*mask//255).astype(np.uint8);stored=im.info.get('NoWave.SourceCoverage');saved=np.frombuffer(base64.b64decode(stored),dtype=np.uint8).reshape(256,256) if stored else dst[:,:,3]
  assert np.array_equal(alpha,saved)
  assert np.all(dst[:,:,3]<=mask)
  assert np.array_equal(dst[src[:,:,3]==255,:3],src[src[:,:,3]==255,:3])
  row={'tile':[z,x,y],'getmap_calls':len(calls),'wms':calls,'generation_s':generated,'visual_cpu_ms':processed*1000,'png_bytes':len(final),'visual_fill':int(im.info['NoWave.VisualFillPixels']),'original_coverage_zero':int((alpha==0).sum()),'display_alpha_zero':int((dst[:,:,3]==0).sum())}
  rows.append(row);(folder/'metrics.json').write_text(json.dumps(row,indent=2));(out/'summary.json').write_text(json.dumps(rows,indent=2));print({k:v for k,v in row.items() if k!='wms'},flush=True)
 await close_marine_service()
asyncio.run(main())
