import json,time,hashlib
from io import BytesIO
from pathlib import Path
import httpx,numpy as np
from PIL import Image
from app.infrastructure.adapters.emodnet_bathymetry import EMODNET_WMS_URL
root=Path('/tmp/nowave-gray-audit');root.mkdir(exist_ok=True)
source=Path('docs/test-reports/artifacts/NW-220-coastal/tiles/14-8462-6014')
params=json.loads((source/'metrics.json').read_text())['wms']
with httpx.Client(timeout=30) as client:
 r=client.get(EMODNET_WMS_URL,params={'service':'WMS','request':'GetCapabilities'});r.raise_for_status();(root/'capabilities.xml').write_bytes(r.content)
 print('Server',r.headers.get('server'),'capabilities',r.content[:120],flush=True)
 results=[]
 for method in ['nearest neighbor','bilinear','bicubic']:
  start=time.perf_counter();r=client.get(EMODNET_WMS_URL,params={**params,'interpolations':method});r.raise_for_status()
  name=method.replace(' ','-');(root/f'wms-{name}.png').write_bytes(r.content)
  a=np.array(Image.open(BytesIO(r.content)).convert('RGBA'))
  results.append({'method':method,'bytes':len(r.content),'time_s':round(time.perf_counter()-start,3),'sha256':hashlib.sha256(r.content).hexdigest(),'partial_alpha':int(((a[:,:,3]>0)&(a[:,:,3]<255)).sum())})
  print(results[-1],flush=True)
 (root/'wms-interpolation.json').write_text(json.dumps(results,indent=2))
