import json,sys
from pathlib import Path
from io import BytesIO
import numpy as np
from PIL import Image
from shapely.geometry import shape
from shapely import union_all, contains_xy
from shapely.affinity import scale
import mapbox_vector_tile
out=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/tmp/nowave-coastal-audit');rows=[]
for folder in sorted(out.glob('14-*')):
 if not (folder/'metrics.json').exists():continue
 raw=Image.open(folder/'source.png').convert('RGBA');rec=Image.open(folder/'recolored.png').convert('RGBA');pre=Image.open(folder/'feather.png').convert('RGBA');mask=np.array(Image.open(folder/'mask.png'));final=Image.open(folder/'final.png').convert('RGBA')
 a=np.array(raw)[:,:,3];p=np.array(pre)[:,:,3];f=np.array(final)[:,:,3]
 decoded=mapbox_vector_tile.decode((folder/'coast.mvt').read_bytes())
 geoms=[]
 for layer, data in decoded.items():
  if layer not in ['ocean','water_polygons']:continue
  for feature in data['features']:
   if layer=='water_polygons' and feature['properties'].get('kind') not in ['dock','canal']:continue
   geoms.append(scale(shape(feature['geometry']),xfact=256/data['extent'],yfact=256/data['extent'],origin=(0,0)))
 water=union_all(geoms);ys,xs=np.indices((256,256));inside=contains_xy(water,xs+.5,255.5-ys)
 row=dict(tile=folder.name,alpha_lut_exact=bool(np.array_equal(a,np.array(rec)[:,:,3])),feather_never_extends=bool(np.all(p<=a)),mask_never_extends=bool(np.all(f<=p)),mask_centres_exact=bool(np.array_equal(mask>0,inside)),nodata_in_water=int(((a==0)&inside).sum()),mask_excluded_water_centres=int(((mask==0)&inside).sum()),source_opaque_in_land=int(((a==255)&~inside).sum()))
 rows.append(row)
(out/'counteraudit.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows,indent=2))
