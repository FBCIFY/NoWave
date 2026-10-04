"""Fetch and prepare the small Cassis pilot. No synthetic depths or objects.

Raw downloads stay in an external cache; only clipped inputs and outputs are
published. --offline rebuilds from that cache. Network access is explicit.
"""
import argparse
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import urllib.parse
import urllib.request

import contourpy
import numpy as np
from PIL import Image
import py7zr
from py7zr.io import Py7zIO, WriterFactory
import rasterio
from rasterio.windows import from_bounds as window_from_bounds, Window
from scipy.interpolate import LinearNDInterpolator
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import polygonize, unary_union

from build_style import COLORS

ROOT = Path(__file__).resolve().parents[1]
BBOX = (5.515, 43.19, 5.555, 43.225)
SURVEY = 'S201300200'
SHOM = 'https://services.data.shom.fr'
HOMONIM_URL = (SHOM+'/INSPIRE/telechargement/prepackageGroup/'
    'MNT_MED100m_GDL_CA_HOMONIM_PBMA_4326_PACK_DL/prepackage/'
    'MNT_FACADE_GDL-CA_HOMONIM_PBMA/file/MNT_FACADE_GDL-CA_HOMONIM_PBMA.7z')
SURVEY_URL = (SHOM+'/INSPIRE/telechargement/prepackageGroup/'
    f'LEVES_BATHY_APRES_2005_PACK_DL/prepackage/{SURVEY}/file/{SURVEY}.7z')
OSM_ATTRIBUTION = '© OpenStreetMap contributors · ODbL 1.0'
HOMONIM_ATTRIBUTION = 'Shom, 2015. MNT Golfe du Lion–Côte d’Azur (HOMONIM), PBMA · doi:10.17183/MNT_MED100m_GDL_CA_HOMONIM_WGS84'
SURVEY_ATTRIBUTION = 'Shom, levé S201300200 (2007–2013), ZH assimilé PBMA · doi:10.17183/S201300200 · Licence Ouverte 2.0'


def request(url, **kwargs):
    return urllib.request.urlopen(urllib.request.Request(url, headers={
        'User-Agent': 'NoWave-Cassis-pilot/1.0', **kwargs.pop('headers', {})}, **kwargs), timeout=120)


def cached(cache, name, url, offline):
    target = cache/name
    if not target.exists():
        if offline:
            raise FileNotFoundError(f'Missing cache {target}; run without --offline')
        with request(url) as response:
            target.write_bytes(response.read())
    return target


def fetch_osm(cache, offline):
    """Prefer Overpass meta+geom; preserve the returned source tags and IDs."""
    target = cache/'osm.json'
    if target.exists():
        return json.loads(target.read_text())
    if offline:
        raise FileNotFoundError(target)
    # Slight buffer supplies continuous coast ways through the clip rectangle.
    b = '43.18,5.50,43.225,5.565'
    query = (f'[out:json][timeout:90];(nwr["leisure"="marina"]({b});'
        f'nwr["harbour"]({b});nwr["waterway"="dock"]({b});'
        f'nwr["man_made"~"^(pier|breakwater|groyne|quay)$"]({b});'
        f'nwr[~"^seamark:"~"."]({b});way["natural"="coastline"]({b});'
        f'nwr["natural"="water"]({b});nwr["landuse"~"^(forest|residential)$"]({b});'
        f'node["place"="town"]({b}););out meta geom;')
    (cache/'overpass-query.txt').write_text(query)
    errors = []
    for endpoint in ['https://overpass.kumi.systems/api/interpreter',
                     'https://overpass-api.de/api/interpreter']:
        try:
            with request(endpoint, data=urllib.parse.urlencode({'data': query}).encode()) as r:
                data = json.loads(r.read())
            if 'elements' not in data or 'remark' in data:
                raise ValueError('Incomplete Overpass response')
            data['nowave_endpoint'] = endpoint
            target.write_text(json.dumps(data))
            return data
        except (OSError, ValueError) as error:
            errors.append(f'{endpoint}: {error}')
    raise RuntimeError('Overpass failed: '+'; '.join(errors))


class RemoteArchive(io.RawIOBase):
    """Range-stream a public indivisible SHOM archive without saving it globally."""
    def __init__(self, url):
        self.url, self.pos, self.total = url, 0, 0
        self.block_start, self.block = -1, b''
        with request(url, method='HEAD') as response:
            self.length = int(response.headers['Content-Length'])

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos+offset if whence == 1 else self.length+offset
        return self.pos

    def read(self, size=-1):
        size = self.length-self.pos if size < 0 else min(size, self.length-self.pos)
        output = []
        while size > 0:
            # py7zr makes small sequential reads. Read ahead avoids thousands
            # of HTTP requests; only one 8 MiB block is held at a time.
            if not self.block_start <= self.pos < self.block_start+len(self.block):
                start = self.pos
                count = min(8*1024*1024, self.length-start)
                for attempt in range(3):
                    try:
                        with request(self.url, headers={'Range': f'bytes={start}-{start+count-1}'}) as r:
                            if r.status != 206: raise ValueError('Server must support HTTP Range')
                            if not r.headers.get('Content-Range', '').startswith(f'bytes {start}-'):
                                raise ValueError('Wrong HTTP range')
                            data = r.read()
                        if len(data) != count: raise ValueError('Incomplete range')
                        break
                    except OSError:
                        if attempt == 2: raise
                self.block_start, self.block = start, data
                self.total += len(data)
                if self.total//(50*1024*1024) != (self.total-len(data))//(50*1024*1024):
                    print(f'SHOM archive streamed: {self.total//1048576} MiB', flush=True)
            offset = self.pos-self.block_start
            take = min(size, len(self.block)-offset)
            output.append(self.block[offset:offset+take])
            self.pos += take
            size -= take
        return b''.join(output)


class ClippedXYZ(Py7zIO):
    def __init__(self):
        self.pending, self.chunks, self.bytes, self.count = b'', [], 0, 0
        self.header_lines = 3

    def write(self, data):
        self.bytes += len(data)
        buffer = self.pending+data
        end = buffer.rfind(b'\n')
        if end < 0:
            self.pending = buffer
            return len(data)
        self.pending = buffer[end+1:]
        self.consume(buffer[:end])
        return len(data)

    def consume(self, data):
        while self.header_lines and data:
            _, separator, data = data.partition(b'\n')
            self.header_lines -= 1
        if not data.strip(): return
        values = np.fromstring(data.decode('ascii').replace(',', ' '), sep=' ').reshape(-1, 3)
        self.count += len(values)
        w, s, e, n = BBOX
        values = values[(values[:, 0] >= w) & (values[:, 0] <= e) &
                        (values[:, 1] >= s) & (values[:, 1] <= n)]
        if len(values): self.chunks.append(values)

    def read(self, size=None): return b''
    def seek(self, offset, whence=0): return self.bytes
    def flush(self): pass
    def size(self): return self.bytes


class XYZFactory(WriterFactory):
    def __init__(self): self.stream = ClippedXYZ()
    def create(self, filename):
        if not filename.endswith('.xyz'): raise ValueError(filename)
        return self.stream


def fetch_survey(cache, offline):
    target = cache/'survey-points.npz'
    if not target.exists():
        if offline: raise FileNotFoundError(target)
        factory = XYZFactory()
        with RemoteArchive(SURVEY_URL) as source:
            with py7zr.SevenZipFile(source) as archive:
                archive.extract(targets=[f'{SURVEY}/{SURVEY}.xyz'], factory=factory)
            transferred = source.total
        stream = factory.stream
        stream.consume(stream.pending)
        if not stream.chunks: raise ValueError('No measured points in Cassis bbox')
        np.savez_compressed(target, points=np.concatenate(stream.chunks))
        (cache/'survey-download.json').write_text(json.dumps({
            'url': SURVEY_URL, 'bytes_transferred': transferred,
            'source_points_scanned': stream.count, 'bbox': BBOX,
            'method': 'Range stream + XYZ bbox filter; no global XYZ stored'}))
    return np.load(target)['points']


def feature(kind, geom, **properties):
    return {'type': 'Feature', 'geometry': mapping(geom),
            'properties': {'kind': kind, 'demo': False, **properties}}


def osm_geometry(element):
    if element['type'] == 'node': return Point(element['lon'], element['lat'])
    coords = [(p['lon'], p['lat']) for p in element.get('geometry', []) if p]
    if len(coords) < 2: return None
    if coords[0] == coords[-1] and len(coords) >= 4:
        polygon = Polygon(coords)
        return polygon if polygon.is_valid else polygon.buffer(0)
    return LineString(coords)


def coastline_land(elements, extent):
    """OSM directed coastline: land is on its left. Close only at clip edges."""
    segments, coastlines, ids = [], [], []
    for element in elements:
        if element.get('tags', {}).get('natural') != 'coastline': continue
        points = [(p['lon'], p['lat']) for p in element['geometry']]
        line = LineString(points).intersection(extent)
        if line.is_empty: continue
        coastlines.append(line)
        ids.append(f"way/{element['id']}")
        for a, b in zip(points, points[1:]):
            if a != b: segments.append((np.array(a), np.array(b)))
    if not coastlines: raise ValueError('No real coastline')
    coast = unary_union(coastlines)
    polygons = list(polygonize(unary_union([extent.boundary, coast])))
    land = []
    for polygon in polygons:
        point = polygon.representative_point()
        # Use original directed segments; union/polygonize may reverse orientation.
        a, b = min(segments, key=lambda ab: LineString(ab).distance(point))
        vector, delta = b-a, np.array([point.x, point.y])-a
        if vector[0]*delta[1]-vector[1]*delta[0] > 0: land.append(polygon)
    result = unary_union(land)
    if result.is_empty or result.area >= extent.area: raise ValueError('Invalid coastal land closure')
    return result, coast, ids


def normalize_osm(data):
    extent = box(*BBOX)
    elements = data['elements']
    retrieved = data['osm3s']['timestamp_osm_base']
    land, coast, coast_ids = coastline_land(elements, extent)
    provenance = dict(source='OpenStreetMap', retrieved_at=retrieved,
                      license='ODbL-1.0', osm_ids=coast_ids, derived='Directed OSM coastline closed at pilot bbox')
    provenance['osm_inputs'] = [{'osm_id': f"way/{e['id']}", 'osm_tags': e['tags'],
        'osm_timestamp': e.get('timestamp'), 'osm_version': e.get('version')}
        for e in elements if e.get('tags', {}).get('natural') == 'coastline'
        and f"way/{e['id']}" in coast_ids]
    features = [feature('land', land, **provenance)]
    inventory, skipped = [], []
    marina = None
    for element in elements:
        tags = element.get('tags', {})
        geom = osm_geometry(element)
        if geom is None:
            if any(k.startswith('seamark:') for k in tags):
                skipped.append({'osm_id': f"{element['type']}/{element['id']}",
                    'tags': tags, 'reason': 'Relation geometry not normalized; not rendered'})
            continue
        if not geom.intersects(extent): continue
        geom = geom.intersection(extent)
        properties = dict(source='OpenStreetMap', osm_id=f"{element['type']}/{element['id']}",
            osm_tags=tags, osm_version=element.get('version'), osm_timestamp=element.get('timestamp'),
            retrieved_at=retrieved, license='ODbL-1.0', name=tags.get('name', tags.get('seamark:name', '')))
        kind, icon = None, None
        if tags.get('natural') == 'coastline':
            kind = 'coast'
            if geom.geom_type in ('Polygon', 'MultiPolygon'): geom = geom.boundary
        elif tags.get('leisure') == 'marina' or tags.get('seamark:type') == 'harbour':
            kind, icon = 'port', 'port-marina'
            marina = geom if geom.geom_type in ('Polygon', 'MultiPolygon') else marina
            properties['derived'] = 'Label point from mapped marina geometry'
            if marina is not None:
                features.append(feature('marina_extent', marina, **properties))
            geom = geom.representative_point()
        elif tags.get('man_made') in ('pier', 'breakwater', 'groyne', 'quay'):
            kind = {'pier': 'pontoon', 'breakwater': 'breakwater', 'groyne': 'breakwater', 'quay': 'quay'}[tags['man_made']]
            if geom.geom_type in ('Polygon', 'MultiPolygon'):
                properties['derived'] = 'Mapped pier outline; not an inferred centreline'
                geom = geom.boundary
        elif tags.get('seamark:type') in ('light_minor', 'light_major'):
            prefix = 'seamark:light:' if 'seamark:light:colour' in tags else 'seamark:light:1:'
            color = tags.get(prefix+'colour')
            kind = 'light' if tags['seamark:type'] == 'light_minor' else 'lighthouse'
            if color not in ('red', 'green', 'white', 'yellow'): kind = None
            else:
                icon = 'light-'+color if kind == 'light' else 'lighthouse'
                group = tags.get(prefix+'group', '')
                properties['characteristic'] = (tags.get(prefix+'character', '')+
                    (f'({group})' if group else '')+' '+color+' '+tags.get(prefix+'period', '')+'s').strip()
        elif tags.get('landuse') == 'forest' and geom.geom_type in ('Polygon', 'MultiPolygon'):
            kind = 'vegetation'
            geom = geom.intersection(land)
        elif tags.get('landuse') == 'residential' and geom.geom_type in ('Polygon', 'MultiPolygon'):
            kind = 'urban'
            geom = geom.intersection(land)
        elif tags.get('place') == 'town': kind = 'coastal_town'
        if kind and not geom.is_empty:
            if icon: properties['icon'] = icon
            features.append(feature(kind, geom, **properties))
            inventory.append({'osm_id': properties['osm_id'], 'kind': kind, 'tags': tags})
        elif any(k.startswith('seamark:') for k in tags):
            skipped.append({'osm_id': properties['osm_id'], 'tags': tags,
                            'reason': 'No supported precise normalization; not rendered'})
    return features, land, marina, inventory, skipped


def homonim_grid(cache, offline):
    file = cache/'homonim.asc'
    if not file.exists():
        archive = cached(cache, 'homonim.7z', HOMONIM_URL, offline)
        with py7zr.SevenZipFile(archive) as package:
            path = next(n for n in package.getnames() if n.endswith('.asc'))
            package.extract(path=cache/'homonim-extracted', targets=[path])
        file.write_bytes((cache/'homonim-extracted'/path).read_bytes())
    with rasterio.open(file) as source:
        window = window_from_bounds(*BBOX, source.transform).round_offsets().round_lengths()
        window = Window(window.col_off-1, window.row_off-1, window.width+2, window.height+2)
        values = source.read(1, window=window, masked=True)
        transform = source.window_transform(window)
    # ZNEG = altitude relative to PBMA. Preserve terrestrial/NoData masking.
    depths = np.where(values.mask | (values.data > 0), np.nan, -values.data)
    xs = transform.c+(np.arange(values.shape[1])+.5)*transform.a
    ys = transform.f+(np.arange(values.shape[0])+.5)*transform.e
    return xs, ys, depths


def make_bathymetry(cache, offline, land, marina):
    xs, ys, coarse = homonim_grid(cache, offline)
    points = fetch_survey(cache, offline)
    # SHOM XYZ is longitude, latitude, depth in metres (positive below ZH).
    wet = points[(points[:, 2] >= 0) & (points[:, 2] < 1000)]
    # Filter with the real vector coastline before averaging. Negative XYZ is land.
    from shapely import contains_xy
    wet = wet[~contains_xy(land, wet[:, 0], wet[:, 1])]
    # Keep the clipped measured input, never the global point cloud.
    np.savez_compressed(ROOT/'data/cassis/survey-points.npz', points=points)
    # Aggregate actual observations into 10 m metric cells, reduce triangulation cost.
    scale = np.array([111320*np.cos(np.deg2rad(43.21)), 111320])
    origin = np.array(BBOX[:2])
    xy = (wet[:, :2]-origin)*scale
    cell = np.floor(xy/10).astype(np.int64)
    _, index = np.unique(cell, axis=0, return_inverse=True)
    counts = np.bincount(index)
    means = np.column_stack([np.bincount(index, weights=wet[:, i])/counts for i in range(3)])
    metric = (means[:, :2]-origin)*scale
    # 10 m grid, ~4 MB compressed field. Color and contours use precisely this field.
    width = int(np.ceil((BBOX[2]-BBOX[0])*scale[0]/10))
    height = int(np.ceil((BBOX[3]-BBOX[1])*scale[1]/10))
    x = BBOX[0]+(np.arange(width)+.5)*(BBOX[2]-BBOX[0])/width
    y = BBOX[3]-(np.arange(height)+.5)*(BBOX[3]-BBOX[1])/height
    xx, yy = np.meshgrid(x, y)
    positions = np.column_stack([xx.ravel(), yy.ravel()])
    query = (positions-origin)*scale
    interpolator = LinearNDInterpolator(metric, means[:, 2], fill_value=np.nan)
    surveyed = interpolator(query)
    nearest = cKDTree(metric).query(query)[0]
    # Reject wide gaps and long Delaunay bridges: no extrapolation beyond measured support.
    triangles = interpolator.tri.find_simplex(query)
    accepted = triangles >= 0
    vertices = interpolator.tri.simplices[np.maximum(triangles, 0)]
    triangle_xy = metric[vertices]
    edges = np.stack([np.linalg.norm(triangle_xy[:, 0]-triangle_xy[:, 1], axis=1),
                      np.linalg.norm(triangle_xy[:, 1]-triangle_xy[:, 2], axis=1),
                      np.linalg.norm(triangle_xy[:, 2]-triangle_xy[:, 0], axis=1)])
    accepted &= (nearest <= 20) & (edges.max(axis=0) <= 40)
    surveyed[~accepted] = np.nan
    surveyed = surveyed.reshape(height, width)
    # Regional fallback only where all four original HOMONIM cells are valid.
    from scipy.interpolate import RegularGridInterpolator
    fallback = RegularGridInterpolator((ys[::-1], xs), coarse[::-1], bounds_error=False, fill_value=np.nan)(
        np.column_stack([positions[:, 1], positions[:, 0]])).reshape(height, width)
    # Never apply 111 m regional cells to the mapped port interior.
    if marina is not None:
        fallback[contains_xy(marina, xx, yy)] = np.nan
    is_land = contains_xy(land, xx, yy)
    surveyed[is_land] = np.nan
    depths = np.where(np.isfinite(surveyed), surveyed, fallback)
    depths[is_land] = np.nan
    source_grid = np.where(np.isfinite(surveyed), 2, np.where(np.isfinite(depths), 1, 0)).astype('uint8')
    np.savez_compressed(ROOT/'data/cassis/depth-grid.npz', x=x, y=y, depth_m=depths, source=source_grid)
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    stops = np.array([d for d, _ in COLORS])
    colors = np.array([[int(c[i:i+2], 16) for i in (1, 3, 5)] for _, c in COLORS])
    for i in range(3):
        rgba[:, :, i] = np.nan_to_num(np.interp(depths, stops, colors[:, i])).astype('uint8')
    rgba[:, :, 3] = np.where(np.isfinite(depths), 255, 0)
    Image.fromarray(rgba).save(ROOT/'assets/cassis-bathymetry.png')
    contours = []
    for mask, levels, resolution, source in [
        (source_grid == 2, [2, 5, 10, 20, 30, 50, 75, 100], 10, SURVEY),
        (source_grid == 1, [10, 20, 30, 50, 75, 100], 111, 'HOMONIM')]:
        field = np.ma.masked_where(~mask, depths)
        generator = contourpy.contour_generator(x=x, y=y, z=field, corner_mask=False)
        for level in levels:
            for coordinates in generator.lines(level):
                if len(coordinates) < 2: continue
                line = LineString(coordinates).simplify(.000015, preserve_topology=True)
                if line.length < .00015: continue
                contours.append(feature('contour', line, depth_m=level, source='SHOM '+source,
                    resolution_m=resolution, vertical_reference='PBMA / ZH assimilé PBMA'))
    stats = {'survey': SURVEY, 'survey_dates': ['2007-09-30', '2013-07-12'],
        'points_in_bbox': len(points), 'wet_points': len(wet), 'occupied_10m_cells': len(means),
        'grid_dimensions': [width, height], 'grid_spacing_m': 10,
        'homonim_resolution_degrees': .001, 'homonim_resolution_m_approx': 111,
        'survey_interpolation': '10 m cell means; linear Delaunay; nearest <=20 m; all triangle edges <=40 m; no extrapolation',
        'source_cells': {str(i): int((source_grid == i).sum()) for i in (0, 1, 2)},
        'depth_range_m': [float(np.nanmin(depths)), float(np.nanmax(depths))],
        'contour_count': len(contours)}
    if marina is not None:
        port_cells = contains_xy(marina, xx, yy) & ~is_land
        stats['marina_water_grid_cells'] = int(port_cells.sum())
        stats['marina_surveyed_grid_cells'] = int(((source_grid == 2) & port_cells).sum())
    return contours, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=Path.home()/'.cache/nowave-cassis')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    output = ROOT/'data/cassis'
    output.mkdir(parents=True, exist_ok=True)
    data = fetch_osm(args.cache, args.offline)
    features, land, marina, inventory, skipped = normalize_osm(data)
    contours, bathymetry = make_bathymetry(args.cache, args.offline, land, marina)
    features.extend(contours)
    (output/'features.geojson').write_text(json.dumps({'type': 'FeatureCollection', 'features': features}, separators=(',', ':'), ensure_ascii=False)+'\n')
    water = box(*BBOX).difference(land)
    (output/'water.geojson').write_text(json.dumps(feature('water', water, source='OpenStreetMap', demo=False)))
    surveys = []
    for period, typename in [('after-2005', 'LEVES_BATHY_APRES_2005_WFS:leves_bathy_apres_2005'),
                             ('1990-2005', 'LEVES_BATHY_1990-2005_WFS:leves_bathy_1990_2005')]:
        w, s, e, n = BBOX
        url = SHOM+'/INSPIRE/wfs?'+urllib.parse.urlencode(dict(service='WFS', version='2.0.0',
            request='GetFeature', typeNames=typename, outputFormat='application/json',
            srsName='EPSG:4326', bbox=f'{s},{w},{n},{e},urn:ogc:def:crs:EPSG::4326'))
        raw = json.loads(cached(args.cache, 'surveys-'+period+'.json', url, args.offline).read_text())
        for f in raw['features']:
            g = shape(f['geometry']).intersection(box(*BBOX))
            if not g.is_empty:
                surveys.append(feature('survey_coverage', g, period=period, **f['properties']))
    (output/'survey-coverage.geojson').write_text(json.dumps({'type': 'FeatureCollection', 'features': surveys}, separators=(',', ':')))
    for name, identifier in [('homonim', 'MNT_MED100m_GDL_CA_HOMONIM_WGS84.xml'), ('survey', SURVEY+'_LEVE_BATHY')]:
        url = SHOM+'/geonetwork/INSPIRE?'+urllib.parse.urlencode(dict(service='CSW', version='2.0.2', request='GetRecordById', Id=identifier, elementSetName='full'))
        p = cached(args.cache, name+'-metadata.xml', url, args.offline)
        (output/(name+'-metadata.xml')).write_bytes(p.read_bytes())
    manifest = {'mode': 'CASSIS_REAL', 'bbox': BBOX, 'center': [5.536, 43.2105], 'zoom': 14.5,
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'retrieved_at': datetime.fromtimestamp((args.cache/'survey-points.npz').stat().st_mtime, timezone.utc).isoformat(),
        'osm_timestamp': data['osm3s']['timestamp_osm_base'],
        'osm_endpoint': data.get('nowave_endpoint', 'https://overpass.kumi.systems/api/interpreter'),
        'osm_inventory': inventory, 'osm_not_rendered': skipped,
        'bathymetry': bathymetry,
        'sources': {'osm': OSM_ATTRIBUTION, 'homonim': HOMONIM_ATTRIBUTION, 'survey': SURVEY_ATTRIBUTION},
        'download': json.loads((args.cache/'survey-download.json').read_text()) if (args.cache/'survey-download.json').exists() else {'url': SURVEY_URL, 'method': 'Range stream; clipped XYZ only cached'},
        'coordinates': [[BBOX[0], BBOX[3]], [BBOX[2], BBOX[3]], [BBOX[2], BBOX[1]], [BBOX[0], BBOX[1]]]}
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps(bathymetry, indent=2))
    print(f'OSM objects: {len(inventory)}; contours: {len(contours)}; {output}')


if __name__ == '__main__': main()
