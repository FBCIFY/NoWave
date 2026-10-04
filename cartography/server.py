"""Local static/style/MBTiles server; no connection to the NoWave backend."""
import argparse
import json
import mimetypes
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT/'tools'))
from build_style import outside_mask, relief_source, build_cassis


def make_style(base, mbtiles=None, bathymetry=None, relief=None, attribution=None, center=None, relief_attribution=None, relief_preview=False, zoom=None, real_cassis=False):
    if real_cassis and (mbtiles or relief_preview):
        raise ValueError('CASSIS_REAL, MBTiles and relief-preview are separate modes')
    style = build_cassis() if real_cassis else json.loads((ROOT/'style.json').read_text())
    if center:
        style['center'] = center
    if zoom is not None:
        style['zoom'] = zoom
    if relief and not relief_attribution:
        raise ValueError('Custom DEM tiles require --relief-attribution')
    if relief:
        style['sources']['relief'] = relief_source(relief, relief_attribution)
        style['metadata']['nowave:relief_label'] = 'réel externe fourni (Terrarium)'
    if relief_preview:
        land_color = next(l['paint']['fill-color'] for l in style['layers'] if l['id'] == 'land')
        mask = json.loads((ROOT/'assets/mapzen-preview-sea-mask.json').read_text())
        style['metadata']['nowave:data_mode'] = 'RELIEF_REAL_PREVIEW'
        style['center'] = center or [5.5, 43.22]
        style['zoom'] = zoom if zoom is not None else 12
        style['sources'] = {
            'relief': style['sources']['relief'],
            'relief-sea-mask': {'type': 'image', 'url': '{base}/assets/mapzen-preview-sea-mask.png',
                              'coordinates': mask['coordinates']},
            'relief-outside': {'type': 'geojson', 'data': outside_mask(mask['coordinates'])}}
        style['layers'] = [l for l in style['layers'] if l['id'] in (
            'sea', 'land-relief', 'relief-outside-scene', 'relief-sea-mask')]
        style['layers'][0]['paint']['background-color'] = land_color
    if mbtiles:
        if not bathymetry or not attribution:
            raise ValueError('MBTiles requires bathymetry raster tiles and a source attribution')
        style['metadata']['nowave:data_mode'] = 'DONNEES_FOURNIES'
        style['center'] = center or [0, 0]
        style['sources'] = {
            'features': {'type': 'vector', 'tiles': [base+'/tiles/{z}/{x}/{y}.pbf'],
                         'minzoom': 0, 'maxzoom': 18, 'attribution': attribution},
            'bathymetry': {'type': 'raster', 'tiles': [bathymetry], 'tileSize': 256}}
        if relief:
            style['sources']['relief'] = relief_source(relief, relief_attribution)
        for layer in style['layers']:
            if layer.get('source') == 'features':
                layer['source-layer'] = 'nowave'
        if relief:
            land = next(l for l in style['layers'] if l['id'] == 'land')
            style['layers'].remove(land)
            index = next(i for i, l in enumerate(style['layers']) if l['id'] == 'land-relief')
            style['layers'].insert(index, land)
        style['layers'] = [l for l in style['layers'] if l['id'] not in ('relief-outside-scene', 'relief-sea-mask')
                           and (relief or l['id'] != 'land-relief')]
    # Replace only the base placeholder; glyph/tile placeholders belong to MapLibre.
    return json.loads(json.dumps(style).replace('{base}', base))


def read_tile(path, z, x, y):
    if not 0 <= z <= 22 or not 0 <= x < 2**z or not 0 <= y < 2**z:
        return None
    with sqlite3.connect(f'file:{Path(path).resolve()}?mode=ro', uri=True) as connection:
        row = connection.execute(
            'SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?',
            (z, x, 2**z-1-y)).fetchone()
    return bytes(row[0]) if row else None


def handler_class(config):
    class Handler(BaseHTTPRequestHandler):
        def respond(self, data, content_type, status=200, gzip=False):
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Cache-Control', 'no-cache')
            if gzip:
                self.send_header('Content-Encoding', 'gzip')
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = unquote(urlsplit(self.path).path)
            if '..' in Path(path).parts:
                self.respond(b'Not found', 'text/plain', 404)
                return
            if path == '/health':
                self.respond(b'{"status":"ok"}', 'application/json')
                return
            if path == '/style.json':
                base = config.public_url or 'http://'+self.headers.get('Host', '127.0.0.1:8765')
                style = make_style(base.rstrip('/'), config.mbtiles, config.bathymetry_tiles,
                                   config.relief_tiles, config.attribution, config.center,
                                   getattr(config, 'relief_attribution', None),
                                   getattr(config, 'relief_preview', False), getattr(config, 'zoom', None),
                                   getattr(config, 'real_cassis', False))
                self.respond(json.dumps(style, ensure_ascii=False).encode(), 'application/json')
                return
            if path.startswith('/tiles/bathymetry/'):
                file = (ROOT/path.lstrip('/')).resolve()
                tiles_root = (ROOT/'tiles'/'bathymetry').resolve()

                if (not file.is_relative_to(tiles_root)
                        or not file.is_file()
                        or file.suffix.lower() != '.png'):
                    self.respond(b'Not found', 'text/plain', 404)
                    return

                self.respond(file.read_bytes(), 'image/png')
                return

            if path.startswith('/tiles/vector/cassis/'):
                try:
                    relative = path[len('/tiles/vector/cassis/'):].split('/')
                    if len(relative) != 3:
                        raise ValueError('Expected z/x/y.pbf')

                    z, x, filename = relative

                    if not filename.endswith('.pbf'):
                        raise ValueError('Expected .pbf')

                    data = read_tile(
                        ROOT/'tiles/vector/cassis.mbtiles',
                        int(z),
                        int(x),
                        int(filename[:-4]),
                    )
                except (ValueError, sqlite3.Error):
                    self.respond(b'Invalid tile request', 'text/plain', 400)
                    return

                if data is None:
                    self.respond(
                        b'',
                        'application/vnd.mapbox-vector-tile',
                        204,
                    )
                else:
                    self.respond(
                        data,
                        'application/vnd.mapbox-vector-tile',
                        gzip=data[:2] == b'\x1f\x8b',
                    )
                return

            if path.startswith('/tiles/') and config.mbtiles:
                try:
                    _, _, z, x, filename = path.split('/')
                    if not filename.endswith('.pbf'):
                        raise ValueError('Expected .pbf')
                    data = read_tile(config.mbtiles, int(z), int(x), int(filename[:-4]))
                except (ValueError, sqlite3.Error):
                    self.respond(b'Invalid tile request', 'text/plain', 400)
                    return
                if data is None:
                    self.respond(b'', 'application/vnd.mapbox-vector-tile', 204)
                else:
                    self.respond(data, 'application/vnd.mapbox-vector-tile', gzip=data[:2] == b'\x1f\x8b')
                return
            file = (ROOT/path.lstrip('/')).resolve()
            if (not any(file.is_relative_to(ROOT/directory) for directory in ('assets', 'data')) or not file.is_file()
                    or not path.startswith(('/assets/', '/data/'))):
                self.respond(b'Not found', 'text/plain', 404)
                return
            # Real-data mode must not accidentally expose synthetic inputs.
            if ((config.mbtiles and (path.startswith('/data/') or 'demo-' in path))
                    or (getattr(config, 'real_cassis', False) and
                        (file == ROOT/'data/demo.geojson' or 'demo-' in file.name or 'mapzen-preview-sea-mask' in file.name))):
                self.respond(b'Not found', 'text/plain', 404)
                return
            content_type = 'application/x-protobuf' if file.suffix == '.pbf' else (
                mimetypes.guess_type(file)[0] or 'application/octet-stream')
            self.respond(file.read_bytes(), content_type)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--public-url', help='URL reachable from the test device')
    parser.add_argument('--mbtiles', type=Path, help='Normalized MVT archive, layer nowave')
    parser.add_argument('--bathymetry-tiles', help='Precolored real raster URL with {z}/{x}/{y}')
    parser.add_argument('--relief-tiles', help='Land-only Terrarium DEM tiles; optional')
    parser.add_argument('--relief-attribution', help='Required credits for a custom DEM')
    parser.add_argument('--relief-preview', action='store_true', help='Real Marseille/Cassis terrain only; no demo bathymetry or objects')
    parser.add_argument('--real-cassis', action='store_true', help='Real Cassis pilot: OSM + SHOM, no demo data')
    parser.add_argument('--zoom', type=float, help='Initial zoom (4–18)')
    parser.add_argument('--attribution', help='Sources, dates, licenses')
    parser.add_argument('--center', nargs=2, type=float, metavar=('LON', 'LAT'))
    config = parser.parse_args()
    if config.relief_tiles and not config.relief_attribution:
        parser.error('--relief-tiles requires --relief-attribution')
    if config.real_cassis:
        if config.relief_preview or config.mbtiles:
            parser.error('--real-cassis is separate from --relief-preview and --mbtiles')
        if not (ROOT/'data/cassis/manifest.json').is_file():
            parser.error('Prepare Cassis first: see tools/prepare_cassis.py')
    if config.relief_preview and config.mbtiles:
        parser.error('--relief-preview and --mbtiles are separate modes')
    if config.zoom is not None and not 4 <= config.zoom <= 18:
        parser.error('--zoom must be between 4 and 18')
    if config.mbtiles:
        if not config.mbtiles.is_file():
            parser.error('MBTiles file does not exist')
        try:
            make_style('http://localhost', config.mbtiles, config.bathymetry_tiles,
                       config.relief_tiles, config.attribution, config.center, config.relief_attribution)
            with sqlite3.connect(f'file:{config.mbtiles.resolve()}?mode=ro', uri=True) as connection:
                metadata = dict(connection.execute('SELECT name, value FROM metadata'))
                if metadata.get('format') not in ('pbf', 'mvt'):
                    parser.error('Expected vector MBTiles (pbf/mvt)')
                layers = json.loads(metadata.get('json', '{}')).get('vector_layers', [])
                if not any(l['id'] == 'nowave' for l in layers):
                    parser.error('Expected normalized source-layer nowave; see DATA_CONTRACT.md')
        except (ValueError, sqlite3.Error) as error:
            parser.error(str(error))
    mode = 'CASSIS_REAL — OSM / SHOM / Mapzen' if config.real_cassis else 'DONNEES_FOURNIES' if config.mbtiles else 'RELIEF REEL EXTERNE — bathymétrie et objets fictifs dans la scène de démo'
    print(f'NoWave {mode}\nhttp://{config.host}:{config.port}/style.json', flush=True)
    ThreadingHTTPServer((config.host, config.port), handler_class(config)).serve_forever()


if __name__ == '__main__':
    main()
