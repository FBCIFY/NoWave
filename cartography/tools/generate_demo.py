"""Entirely fictitious island, depths and objects: NEVER navigation data."""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops
from build_style import COLORS, ROOT

FEATURES = []


def feature(kind, geometry, coordinates, **properties):
    FEATURES.append({'type': 'Feature', 'properties': {'kind': kind, 'demo': True, **properties},
                     'geometry': {'type': geometry, 'coordinates': coordinates}})


def radius(t):
    return 1 + .16*math.sin(3*t) + .09*math.cos(5*t) - .12*math.cos(t)


def ring(scale=1, cx=0, cy=0, rx=.045, ry=.032):
    return [[cx+rx*scale*radius(t)*math.cos(t), cy+ry*scale*radius(t)*math.sin(t)]
            for t in [i*math.tau/512 for i in range(513)]]


def rect(x, y, w, h):
    return [[[x, y], [x+w, y], [x+w, y+h], [x, y+h], [x, y]]]


def rgb(color):
    return tuple(int(color[i:i+2], 16) for i in (1, 3, 5))


def depth_color(depth):
    for (a, ca), (b, cb) in zip(COLORS, COLORS[1:]):
        if depth <= b:
            f = max(0, (depth-a)/(b-a))
            return tuple(round(x+(y-x)*f) for x, y in zip(rgb(ca), rgb(cb)))
    return rgb(COLORS[-1][1])


def depth(x, y):
    t = math.atan2(y/.032, x/.045)
    relative = math.hypot(x/.045, y/.032)/radius(t)
    return max(0, relative-1)**1.6 * 140


def rasters():
    n = 1536
    bathy = Image.new('RGB', (n, n))
    relief = Image.new('RGBA', (n, n))
    bp, rp = bathy.load(), relief.load()
    for py in range(n):
        y = .3 - (py+.5)/n*.6
        for px in range(n):
            x = -.3 + (px+.5)/n*.6
            d = depth(x, y)
            bp[px, py] = depth_color(d)
            if d == 0:
                # Purely illustrative land illumination, masked to the fictitious island.
                alpha = int(65*(.5+.5*math.sin(x*130+y*90)))
                rp[px, py] = (134, 139, 131, alpha)
    bathy.save(ROOT/'assets/demo-bathymetry.png')
    relief.save(ROOT/'assets/demo-relief.png')


def data():
    feature('land', 'Polygon', [ring()])
    feature('coast', 'LineString', ring())
    feature('foreshore', 'Polygon', [ring(1.012), list(reversed(ring()))])
    for x, y in [(.061, .03), (.065, .034), (-.054, .042)]:
        r = ring(cx=x, cy=y, rx=.0012, ry=.0007)
        feature('land', 'Polygon', [r])
        feature('coast', 'LineString', r)
    for d in [2, 5, 10, 20, 30, 50, 75, 100, 200, 500, 1000]:
        feature('contour', 'LineString', ring(1+(d/140)**(1/1.6)), depth_m=d)
    feature('vegetation', 'Polygon', [ring(.6)])
    feature('urban', 'Polygon', rect(.02, -.009, .008, .014))
    feature('road', 'LineString', [[.025, -.017], [.025, .005], [.021, .02]], coastal=True, **{'class': 'primary'})
    feature('basin', 'Polygon', rect(.034, -.006, .004, .007))
    feature('breakwater', 'LineString', [[.033, -.007], [.039, -.007], [.039, -.001]])
    feature('quay', 'LineString', [[.034, -.006], [.034, .001], [.038, .001]])
    for y in [-.004, -.002, 0]:
        feature('pontoon', 'LineString', [[.034, y], [.037, y]])
    feature('channel', 'LineString', [[.039, -.003], [.055, -.003], [.071, -.012]])
    feature('entrance', 'LineString', [[.037, -.002], [.042, -.002]])
    feature('bridge', 'LineString', [[.056, .029], [.063, .031]])
    for i, kind in enumerate(['commercial', 'pleasure', 'marina', 'industrial', 'military']):
        feature('port', 'Point', [.035, -.003+i*.006], name=f'Port {kind} · démo', icon='port-'+kind, rank=i)
    feature('lighthouse', 'Point', [.043, .006], name='Phare · démo', icon='lighthouse', characteristic='Fl(3) 10s', rank=1)
    for i, color in enumerate(['red', 'green', 'yellow', 'white', 'black']):
        feature('light', 'Point', [.039+i*.001, -.007], icon='light-'+color, characteristic='Fl 5s')
    # Sector geometry is synthetic here, and tagged demo on every feature.
    center = [.043, .006]
    sector = [center]+[[center[0]+.013*math.sin(math.radians(t)),
                        center[1]+.013*math.cos(math.radians(t))] for t in range(50, 101)]+[center]
    feature('light_sector', 'Polygon', [sector], color='#D84949')
    buoy_icons = ['lateral-port', 'lateral-starboard', 'cardinal-n', 'cardinal-e',
                  'cardinal-s', 'cardinal-w', 'safe-water', 'special', 'isolated-danger',
                  'buoy-sphere', 'buoy-spar']
    for i, icon in enumerate(buoy_icons):
        feature('buoy', 'Point', [.045+(i%4)*.003, -.012-(i//4)*.003],
                icon=icon, name=f'D{i+1} · démo', characteristic='Fl 4s', virtual=False)
    feature('beacon', 'Point', [.047, .02], icon='beacon', name='Balise · démo', virtual=False)
    for kind, pos, icon in [('anchorage', [.058, .015], 'anchor'),
                             ('ship_anchorage', [.08, -.025], 'anchor-ship'),
                             ('mooring', [.042, -.004], 'mooring'),
                             ('wreck', [.072, .024], 'wreck'),
                             ('landmark', [.023, .017], 'landmark')]:
        feature(kind, 'Point', pos, icon=icon, name=f'{kind} · démo', identified=True)
    for kind, x, y in [('shoal', .06, .028), ('reef', .07, .035),
                        ('reserve', .07, .05), ('restricted', .09, -.04),
                        ('military', -.08, -.04), ('windfarm', .11, -.01)]:
        feature(kind, 'Polygon', rect(x, y, .009, .006), name=f'{kind} · démo')
    for kind, x, y, name in [('sea_name', .13, .02, 'Mer fictive'),
                             ('coastal_city', .02, -.008, 'Ville · démo'),
                             ('coastal_town', -.025, .016, 'Village · démo'),
                             ('bay_name', .06, -.005, 'Baie fictive'),
                             ('cape_name', .04, .016, 'Pointe · démo'),
                             ('island_name', 0, 0, 'Île fictive'),
                             ('beach_name', .027, -.018, 'Plage · démo'),
                             ('cove_name', -.04, -.013, 'Crique · démo')]:
        feature(kind, 'Point', [x, y], name=name)
    (ROOT/'data/demo.geojson').write_text(json.dumps({'type': 'FeatureCollection',
        'features': FEATURES}, ensure_ascii=False, separators=(',', ':'))+'\n')


def sprites():
    names = ['port-commercial', 'port-pleasure', 'port-marina', 'port-industrial', 'port-military',
             'lighthouse', *['light-'+c for c in ['red', 'green', 'yellow', 'white', 'black']],
             'lateral-port', 'lateral-starboard', 'cardinal-n', 'cardinal-e', 'cardinal-s', 'cardinal-w',
             'safe-water', 'special', 'isolated-danger', 'buoy-sphere', 'buoy-spar', 'beacon',
             'anchor', 'anchor-ship', 'mooring', 'wreck', 'landmark',
             'foreshore-pattern', 'shoal-pattern', 'reef-pattern']
    names += [scheme+'~'+shape for scheme in ['lateral-port', 'lateral-starboard', 'cardinal-n', 'cardinal-e', 'cardinal-s', 'cardinal-w', 'safe-water', 'special', 'isolated-danger'] for shape in ['cone', 'can', 'sphere', 'spar']]
    for ratio in [1, 2]:
        size = 40*ratio
        atlas = Image.new('RGBA', (size*8, size*math.ceil(len(names)/8)))
        metadata = {}
        for index, sprite_name in enumerate(names):
            name, _, shape = sprite_name.partition('~')
            tile = Image.new('RGBA', (80, 80))
            d = ImageDraw.Draw(tile)
            navy, white = '#4F7187', '#F4FBFF'
            colors = {'red': '#D84949', 'green': '#2E9B68', 'yellow': '#D9B64C', 'white': '#F7F7F4', 'black': '#20262C'}
            if 'pattern' in name:
                color = '#667D8B' if name != 'reef-pattern' else '#566F7E'
                for i in range(3 if name != 'reef-pattern' else 7):
                    x, y = (i*29+9)%80, (i*37+17)%80
                    d.ellipse((x, y, x+3, y+2), fill=color)
            else:
                d.ellipse((12, 12, 68, 68), fill=(244, 251, 255, 180))
                if name.startswith('port-') or name.startswith('anchor'):
                    c = {'commercial': '#4F7187', 'pleasure': '#4C9BB8', 'marina': '#67B6B0',
                         'industrial': '#777C83', 'military': '#6F6B78'}.get(name[5:], navy)
                    width = 6 if name == 'anchor-ship' else 4
                    d.ellipse((35, 19, 45, 29), outline=c, width=width)
                    d.line((40, 28, 40, 57), fill=c, width=width)
                    d.line((27, 36, 53, 36), fill=c, width=width)
                    d.arc((21, 34, 59, 62), 0, 180, fill=c, width=width)
                    if name.startswith('port-'):
                        # Category-specific silhouettes as well as colors.
                        if name == 'port-commercial': d.rectangle((19, 50, 29, 56), fill=c)
                        if name == 'port-pleasure': d.polygon([(25, 30), (32, 20), (32, 30)], fill=c)
                        if name == 'port-marina': d.line((21, 63, 59, 63), fill=c, width=3)
                        if name == 'port-industrial': d.rectangle((50, 20, 57, 33), fill=c)
                        if name == 'port-military': d.polygon([(53, 18), (59, 25), (53, 32), (47, 25)], fill=c)
                elif name == 'lighthouse':
                    d.polygon([(30, 58), (34, 28), (46, 28), (50, 58)], fill=navy)
                    d.rectangle((31, 24, 49, 30), fill=navy)
                    d.line((23, 20, 15, 15), fill=navy, width=3)
                    d.line((57, 20, 65, 15), fill=navy, width=3)
                elif name.startswith('light-'):
                    c = colors[name[6:]]
                    d.ellipse((29, 29, 51, 51), fill=c, outline=navy, width=2)
                    for x, y, xx, yy in [(40, 18, 40, 24), (40, 56, 40, 62), (18, 40, 24, 40), (56, 40, 62, 40)]:
                        d.line((x, y, xx, yy), fill=c, width=3)
                elif name == 'wreck':
                    d.polygon([(22, 43), (58, 43), (51, 56), (28, 56)], fill='#D65C5C')
                    d.line((29, 29, 53, 53), fill='#D65C5C', width=5)
                    d.line((53, 29, 29, 53), fill='#D65C5C', width=5)
                elif name == 'landmark':
                    d.polygon([(30, 59), (37, 23), (43, 23), (50, 59)], fill=navy)
                elif name == 'mooring':
                    d.ellipse((28, 28, 52, 52), fill='#67B6B0', outline=navy, width=3)
                    d.line((40, 52, 40, 62), fill=navy, width=3)
                else:
                    c = '#D9B64C' if name in ['special', 'cardinal-n', 'cardinal-e', 'cardinal-s', 'cardinal-w'] else navy
                    if name == 'lateral-port': c = colors['red']
                    if name == 'lateral-starboard': c = colors['green']
                    if name in ['safe-water', 'isolated-danger']: c = colors['red']
                    body = Image.new('L', (80, 80))
                    bd = ImageDraw.Draw(body)
                    shape = shape or ('cone' if name == 'lateral-starboard' else 'sphere' if name in ['buoy-sphere', 'safe-water'] else 'spar' if name in ['buoy-spar', 'beacon'] else 'can')
                    if shape == 'cone': bd.polygon([(40, 32), (27, 57), (53, 57)], fill=255)
                    elif shape == 'sphere': bd.ellipse((27, 32, 53, 58), fill=255)
                    elif shape == 'spar': bd.rectangle((37, 33, 43, 59), fill=255)
                    else: bd.rectangle((29, 33, 51, 57), fill=255)
                    tile.paste(c, (0, 0, 80, 80), body)
                    def band(y0, y1, color):
                        stripe = Image.new('L', (80, 80))
                        ImageDraw.Draw(stripe).rectangle((0, y0, 80, y1), fill=255)
                        tile.paste(color, (0, 0, 80, 80), ImageChops.multiply(body, stripe))
                    if name.startswith('cardinal-'):
                        direction = name[-1]
                        # IALA topmarks: N up/up, E up/down, S down/down, W down/up.
                        for y, up in [(18, direction in 'ne'), (29, direction in 'nw')]:
                            pts = [(40, y-9), (32, y+1), (48, y+1)] if up else [(32, y-9), (48, y-9), (40, y+1)]
                            d.polygon(pts, fill='#20262C')
                        if direction == 'n': band(33, 44, '#20262C')
                        if direction == 's': band(46, 59, '#20262C')
                        if direction == 'e':
                            band(33, 39, '#20262C'); band(51, 59, '#20262C')
                        if direction == 'w': band(41, 49, '#20262C')
                    elif name == 'special':
                        d.line((33, 18, 47, 30), fill=c, width=4); d.line((47, 18, 33, 30), fill=c, width=4)
                    elif name == 'isolated-danger':
                        band(33, 40, '#20262C'); band(51, 59, '#20262C')
                        for y in [15, 25]: d.ellipse((36, y, 44, y+8), fill='#20262C')
                    elif name == 'safe-water':
                        d.rectangle((37, 33, 43, 56), fill=white); d.ellipse((36, 20, 44, 28), fill=c)
                    d.line((24, 62, 56, 62), fill=navy, width=2)
            tile = tile.resize((size, size), Image.Resampling.LANCZOS)
            x, y = index%8*size, index//8*size
            atlas.paste(tile, (x, y))
            metadata[sprite_name] = {'x': x, 'y': y, 'width': size, 'height': size, 'pixelRatio': ratio}
        suffix = '@2x' if ratio == 2 else ''
        atlas.save(ROOT/f'assets/sprite{suffix}.png')
        (ROOT/f'assets/sprite{suffix}.json').write_text(json.dumps(metadata, indent=2)+'\n')


if __name__ == '__main__':
    data()
    sprites()
    rasters()
