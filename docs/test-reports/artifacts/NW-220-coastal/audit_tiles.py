import json, math, sys, time
from pathlib import Path
from io import BytesIO
from concurrent.futures import ThreadPoolExecutor
import httpx, numpy as np, mapbox_vector_tile
from PIL import Image, ImageDraw
from app.infrastructure.adapters import emodnet_bathymetry as b
from app.infrastructure.marine.coastline import rasterize_ocean, apply_ocean_mask

out=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/tmp/nowave-coastal-audit'); out.mkdir(parents=True,exist_ok=True)

def png(data):
 return Image.open(BytesIO(data)).convert('RGBA')
def stats(image):
 a=np.array(image.getchannel('A')); return { 'zero':int((a==0).sum()),'partial':int(((a>0)&(a<255)).sum()),'opaque':int((a==255).sum()) }
def audit(xy):
 z,x,y=xy; stem=f'{z}-{x}-{y}'; d=out/stem;d.mkdir(exist_ok=True)
 bbox=b.web_mercator_tile_bbox(z,x,y); pixel=(bbox[2]-bbox[0])/256
 padded=(bbox[0]-3*pixel,bbox[1]-3*pixel,bbox[2]+3*pixel,bbox[3]+3*pixel)
 params=dict(service='WMS',request='GetMap',version='1.1.1',layers='emodnet:mean_multicolour',styles='',format='image/png',transparent='true',width='262',height='262',srs='EPSG:3857',bbox=','.join(f'{v:.6f}' for v in padded))
 if not (d/'source-padded.png').exists():
  r=b._request_tile(params);r.raise_for_status();(d/'source-padded.png').write_bytes(r.content)
 raw=(d/'source-padded.png').read_bytes(); src=png(raw);src.crop((3,3,259,259)).save(d/'source.png')
 recolored=png(b.recolor_bathymetry_png(raw));recolored.crop((3,3,259,259)).save(d/'recolored.png')
 feather=b.feather_coverage(recolored).crop((3,3,259,259));feather.save(d/'feather.png');feather.getchannel('A').save(d/'alpha-before-mask.png')
 url=f'https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt'
 if not (d/'coast.mvt').exists():
  r=httpx.get(url,timeout=30,headers={'User-Agent':'NoWave coastal diagnostic (one tile per cached request)'});r.raise_for_status();(d/'coast.mvt').write_bytes(r.content)
 coast=(d/'coast.mvt').read_bytes();mask=rasterize_ocean(coast);(d/'mask.png').write_bytes(mask)
 buf=BytesIO();feather.save(buf,format='PNG');final=png(apply_ocean_mask(buf.getvalue(),mask));final.save(d/'final.png')
 final.getchannel('A').save(d/'alpha-final.png')
 for name,img in [('before-mask',feather),('final',final)]:
  bg=Image.new('RGBA',(256,256),'#002D51');Image.alpha_composite(bg,img).convert('RGB').save(d/f'{name}-composite.png')
 a=np.array(src.crop((3,3,259,259)).getchannel('A'));m=np.array(Image.open(BytesIO(mask)));f=np.array(final)
 values={ 'tile':list(xy), 'bbox':bbox,'wms':params,'source':stats(src.crop((3,3,259,259))), 'feather':stats(feather),'final':stats(final),'source_zero_in_osm_water':int(((a==0)&(m==255)).sum()),'valid_source_removed_by_mask':int(((a>0)&(m==0)).sum()),'partial_mask':int(((m>0)&(m<255)).sum()),'layers':{k:{'extent':v['extent'],'features':len(v['features'])} for k,v in mapbox_vector_tile.decode(coast).items()} }
 (d/'metrics.json').write_text(json.dumps(values,indent=2))
 return values

if __name__=='__main__':
 tiles=[tuple(map(int,p.name.split('-'))) for p in sorted(out.glob('14-*'))] or [(14,x,y) for y in [6014,6015] for x in [8461,8462]]
 b._blue_color_lut()  # Build once before diagnostic threads start.
 with ThreadPoolExecutor(max_workers=2) as pool:
  results=list(pool.map(audit,tiles))
 (out/'metrics.json').write_text(json.dumps(results,indent=2))
 for r in results: print(json.dumps({k:v for k,v in r.items() if k not in ['layers','wms','bbox']}),flush=True)
 if len(tiles)!=4: sys.exit(0)
 # Aligned mosaics: each stage uses the same Web Mercator pixel grid.
 for name in ['source','recolored','alpha-before-mask','mask','final','before-mask-composite','final-composite']:
  mosaic=Image.new('RGB',(512,512),'white')
  for i,(_,x,y) in enumerate(tiles):mosaic.paste(Image.open(out/f'14-{x}-{y}'/f'{name}.png').convert('RGB'),((i%2)*256,(i//2)*256))
  mosaic.save(out/f'mosaic-{name}.png')
