"""Entirely fictitious island, depths and objects: NEVER navigation data."""
import json
import math
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops, ImageFilter
from build_style import COLORS, ROOT

FEATURES = []
ISLETS = [(.061, .03), (.065, .034), (-.054, .042), (.072, .052), (.079, .056)]


def feature(kind, geometry, coordinates, **properties):
    def compact(value):
        return [compact(item) for item in value] if isinstance(value, list) else round(float(value), 7)
    coordinates = compact(coordinates)
    FEATURES.append({'type': 'Feature', 'properties': {'kind': kind, 'demo': True, **properties},
                     'geometry': {'type': geometry, 'coordinates': coordinates}})


def radius(t, phase=0, detail=1):
    """Shared organic outline for vector shores and the synthetic seabed."""
    q = t+phase
    outline = (1 + .16*np.sin(3*q) + .09*np.cos(5*q) - .12*np.cos(q)
               + detail*(.035*np.sin(9*q) + .022*np.sin(17*q) + .014*np.cos(31*q)
                         + .008*np.sin(57*q) + .004*np.cos(93*q)))
    # Narrow coves between headlands, rather than an evenly rippled perimeter.
    for angle, width, indentation in [(.55, .13, .11), (2.65, .18, .13), (4.5, .12, .09)]:
        delta = np.arctan2(np.sin(q-angle), np.cos(q-angle))
        outline -= detail*indentation*np.exp(-(delta/width)**2)
    return outline


def ring(scale=1, cx=0, cy=0, rx=.045, ry=.032):
    coordinates = [[cx+rx*scale*float(radius(t, cx*130+cy*170))*math.cos(t), cy+ry*scale*float(radius(t, cx*130+cy*170))*math.sin(t)]
                   for t in [i*math.tau/1536 for i in range(1537)]]
    if cx == cy == 0 and rx == .045 and scale <= 1.012:
        # Deliberately fictitious harbour excavation, connected to the sea.
        for point in coordinates:
            if point[0] > .0338 and -.007 <= point[1] <= .004:
                point[0] = .0338
    return coordinates


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
    """One continuous DEMO field: shelf, asymmetric banks, gullies and fine shallows."""
    t = np.arctan2(y/.032, x/.045)
    coarse_distance = np.maximum(0, np.hypot(x/.045, y/.032)/radius(t, detail=0)-1)
    relative = np.hypot(x/.045, y/.032)/radius(t, detail=np.exp(-coarse_distance*4))
    distance = np.maximum(0, relative-1)
    shelf = distance**1.15 * 210 * (1 + .22*np.sin(5*t+distance*1.7)
                                  + .10*np.cos(2*t-distance*3))
    # Broad offshore structure remains smooth; coastal detail fades with depth.
    shelf *= 1 + .12*np.sin(x*85+y*65)*np.sin(y*110-x*35)
    for cx, cy, rx, ry, shallow, angle in [(.064, .031, .010, .005, 3, -.5),
                                            (.073, .038, .009, .004, 1.3, .65),
                                            (.078, .054, .014, .008, 8, -.4)]:
        u = (x-cx)*np.cos(angle)+(y-cy)*np.sin(angle)
        v = -(x-cx)*np.sin(angle)+(y-cy)*np.cos(angle)
        u += rx*.13*np.sin(y*1800+x*700)
        v += ry*.15*np.sin(x*1500-y*650)
        influence = np.exp(-((u/rx)**2+(v/ry)**2)*1.8)
        target = np.maximum(.5, shallow+.9*np.sin(x*2900)*np.cos(y*2200))
        shelf = shelf*(1-influence)+target*influence
    for cx, cy in ISLETS:
        angle = np.arctan2((y-cy)/.0007, (x-cx)/.0012)
        relative_islet = np.hypot((x-cx)/.0012, (y-cy)/.0007)/radius(angle, cx*130+cy*170)
        local = np.maximum(0, relative_islet-1)**1.15*5
        smoothing = 1 + .06*np.minimum(shelf, local)
        shelf = .5*(shelf+local-np.sqrt((shelf-local)**2+smoothing**2))
    shelf = np.maximum(0, shelf)
    # Narrower submarine gullies cut the banks, without creating extra objects.
    shelf += 13*np.exp(-(((x-.069)/.0012)**2+((y-.030)/.006)**2))
    shallow_weight = np.minimum(1, shelf/5)*np.exp(-shelf/65)
    ripples = (1.6*np.sin(x*1850+y*1250) + .9*np.sin(y*3300-x*900)
               + .6*np.cos(x*4100+y*2300))
    return np.maximum(0, shelf+shallow_weight*ripples)


def simplify_line(line, tolerance=.000025):
    """Douglas-Peucker at roughly 3 m: keep small contours without oversized GeoJSON."""
    points = np.asarray(line)
    keep = {0, len(line)-1}
    stack = [(0, len(line)-1)]
    while stack:
        first, last = stack.pop()
        if last-first < 2:
            continue
        delta = points[last]-points[first]
        relative = points[first+1:last]-points[first]
        length = np.hypot(*delta)
        distances = np.abs(relative[:, 0]*delta[1]-relative[:, 1]*delta[0])/length if length else np.hypot(relative[:, 0], relative[:, 1])
        index = int(np.argmax(distances))
        if distances[index] > tolerance:
            middle = first+1+index
            keep.add(middle)
            stack.extend([(first, middle), (middle, last)])
    return [line[index] for index in sorted(keep)]


def contours(levels):
    """Marching squares over the same synthetic depth field (no invented soundings)."""
    # About 16 m in the coastal scene, coarser offshore: smooth small reef isolines
    # without increasing the whole-domain raster or the mobile texture footprint.
    xs = np.r_[np.linspace(-.24, -.09, 180, endpoint=False),
               np.linspace(-.09, .11, 1401, endpoint=False), np.linspace(.11, .24, 161)]
    ys = np.r_[np.linspace(-.24, -.07, 200, endpoint=False),
               np.linspace(-.07, .09, 1121, endpoint=False), np.linspace(.09, .24, 181)]
    field = depth(xs[None, :], ys[:, None])
    for level in levels:
        adjacency, points = {}, {}
        def key(point):
            value = tuple(round(float(v), 9) for v in point)
            points[value] = list(value)
            return value
        below = field < level
        active = ((below[:-1, :-1] != below[:-1, 1:]) |
                  (below[:-1, :-1] != below[1:, :-1]) |
                  (below[:-1, :-1] != below[1:, 1:]))
        for y, x in np.argwhere(active):
            corners = [(xs[x], ys[y]), (xs[x+1], ys[y]),
                       (xs[x+1], ys[y+1]), (xs[x], ys[y+1])]
            values = [field[y][x], field[y][x+1], field[y+1][x+1], field[y+1][x]]
            crossings = []
            for i, j in [(0, 1), (1, 2), (2, 3), (3, 0)]:
                if (values[i] < level) != (values[j] < level):
                    f = (level-values[i])/(values[j]-values[i])
                    crossings.append(key(tuple(corners[i][k]+f*(corners[j][k]-corners[i][k]) for k in (0, 1))))
            for i in range(0, len(crossings), 2):
                a, b = crossings[i:i+2]
                if a == b:  # An isoline can pass exactly through a grid vertex.
                    continue
                adjacency.setdefault(a, set()).add(b)
                adjacency.setdefault(b, set()).add(a)
        while adjacency:
            start = next((k for k, v in adjacency.items() if len(v) == 1), next(iter(adjacency)))
            line, current = [points[start]], start
            while current in adjacency:
                nxt = next(iter(adjacency[current]))
                adjacency[current].remove(nxt)
                if not adjacency[current]: del adjacency[current]
                adjacency[nxt].remove(current)
                if not adjacency[nxt]: del adjacency[nxt]
                line.append(points[nxt])
                current = nxt
            if len(line) > 5:
                # Sub-grid corner smoothing only; retain closed contours and depth values.
                closed = line[0] == line[-1]
                for _ in range(2):
                    refined = [] if closed else [line[0]]
                    for a, b in zip(line, line[1:]):
                        refined.extend([[.75*a[k]+.25*b[k] for k in (0, 1)],
                                        [.25*a[k]+.75*b[k] for k in (0, 1)]])
                    refined.append(refined[0] if closed else line[-1])
                    line = refined
                feature('contour', 'LineString', simplify_line(line), depth_m=level)


def rasters():
    n = 2048
    axis = -.3 + (np.arange(n)+.5)/n*.6
    depths = depth(axis[None, :], -axis[:, None])
    stops = [d for d, _ in COLORS]
    colors = np.array([rgb(c) for _, c in COLORS])
    channels = [np.rint(np.interp(depths, stops, colors[:, channel])).astype(np.uint8)
                for channel in range(3)]
    Image.fromarray(np.stack(channels, axis=-1)).save(ROOT/'assets/demo-bathymetry.png')


def data():
    feature('land', 'Polygon', [ring()])
    feature('coast', 'LineString', ring())
    feature('foreshore', 'Polygon', [ring(1.012), list(reversed(ring()))])
    for x, y in ISLETS:
        r = ring(cx=x, cy=y, rx=.0012, ry=.0007)
        feature('land', 'Polygon', [r])
        feature('coast', 'LineString', r)
    contours([2, 3, 5, 7.5, 10, 12.5, 15, 20, 25, 30, 40, 50, 60, 75, 100, 150, 200, 300, 500, 1000])
    feature('vegetation', 'Polygon', [ring(.6)])
    feature('urban', 'Polygon', rect(.02, -.009, .008, .014))
    feature('road', 'LineString', [[.025, -.017], [.025, .005], [.021, .02]], coastal=True, **{'class': 'primary'})
    feature('basin', 'Polygon', rect(.034, -.006, .004, .007))
    feature('breakwater', 'LineString', [[.033, -.007], [.039, -.007], [.039, -.001]])
    feature('quay', 'LineString', [[.034, -.006], [.034, .001], [.038, .001]])
    for y in [-.005, -.0035, -.002, -.0005]:
        feature('pontoon', 'LineString', [[.034, y], [.0373, y]])
        for x in [.0345, .0351, .0357, .0363, .0369]:
            feature('pontoon', 'LineString', [[x, y], [x, y+.00048]])
    # A second sheltered basin, a curved outer mole and paired entrance lights.
    feature('basin', 'Polygon', rect(.034, .0013, .0038, .0024))
    feature('quay', 'LineString', [[.034, .0013], [.034, .0037], [.0378, .0037]])
    feature('breakwater', 'LineString', [[.038, .0037], [.0386, .00345], [.0391, .0030], [.03945, .00235], [.0396, .0015], [.0395, .0004], [.039, -.001]])
    for y in [.002, .0029]:
        feature('pontoon', 'LineString', [[.034, y], [.037, y]])
    for pos, color in [([.039, -.001], 'red'), ([.038, -.0037], 'green')]:
        feature('light', 'Point', pos, icon='light-'+color, characteristic='Iso 4s')
    feature('channel', 'LineString', [[.039, -.003], [.055, -.003], [.071, -.012]])
    feature('entrance', 'LineString', [[.037, -.002], [.042, -.002]])
    feature('bridge', 'LineString', [[.056, .029], [.063, .031]])
    for i, kind in enumerate(['pleasure', 'marina', 'commercial', 'industrial', 'military']):
        feature('port', 'Point', [.035, -.003+i*.006], name={'commercial':'Port de commerce', 'pleasure':'Port de plaisance', 'marina':'Marina des Îlots', 'industrial':'Port industriel', 'military':'Base navale'}[kind], icon='port-'+kind, rank=i)
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
        feature('buoy', 'Point', [.050+(i%4)*.003, .003-(i//4)*.003],
                icon=icon, name=f'D{i+1}', characteristic='Fl 4s', virtual=False)
    feature('danger_rock', 'Point', [.0745, .033], icon='danger-rock', name='Rocher · démo')
    feature('beacon', 'Point', [.047, .02], icon='beacon', name='Balise · démo', virtual=False)
    for kind, pos, icon in [('anchorage', [.058, .015], 'anchor'),
                             ('ship_anchorage', [.08, -.025], 'anchor-ship'),
                             ('mooring', [.036, -.0018], 'mooring'),
                             ('wreck', [.072, .030], 'wreck'),
                             ('landmark', [.023, .017], 'landmark')]:
        feature(kind, 'Point', pos, icon=icon, name=f'{kind} · démo', identified=True)
    for kind, x, y in [('shoal', .06, .028), ('reef', .07, .035),
                        ('reserve', .07, .05), ('restricted', .09, -.04),
                        ('military', -.08, -.04), ('windfarm', .11, -.01)]:
        outline = ring(cx=x+.0045, cy=y+.003, rx=.009 if kind == 'reserve' else .0045,
                       ry=.006 if kind == 'reserve' else .003)
        if kind in ('reserve', 'restricted', 'military', 'windfarm'):
            # Regulatory boundaries are smoother than the textured shoreline.
            outline = outline[::8]
            if outline[-1] != outline[0]: outline.append(outline[0])
            for _ in range(2):
                smoothed = []
                for a, b in zip(outline, outline[1:]):
                    smoothed.extend([[.75*a[k]+.25*b[k] for k in (0, 1)],
                                     [.25*a[k]+.75*b[k] for k in (0, 1)]])
                outline = smoothed+[smoothed[0]]
        feature(kind, 'Polygon', [outline], name='Réserve marine des Îlots' if kind == 'reserve' else f'{kind} · démo')
    for kind, x, y, name in [('sea_name', .13, .002, 'Mer fictive'),
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
             'landmark-tower', 'landmark-monument', 'landmark-chimney', 'landmark-pylon', 'danger-rock',
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
                # Deterministic, uneven clusters: sand grains vs. angular reef fragments.
                count = 14 if name == 'reef-pattern' else 10 if name == 'shoal-pattern' else 8
                for i in range(count):
                    x = (i*31+11+int(9*math.sin(i*2.7)))%76
                    y = (i*47+17+int(8*math.cos(i*1.9)))%76
                    if name == 'reef-pattern':
                        d.polygon([(x,y+4),(x+2,y),(x+6,y+1),(x+5,y+5)],
                                  fill=(66,96,110,95), outline=(58,89,103,135))
                        d.line((x+1,y+5,x+5,y+5),fill=(235,248,253,150),width=1)
                    else:
                        d.ellipse((x,y,x+1+(i%2),y+1),fill=(77,115,134,90))
            else:
                if name.startswith('port-'):
                    c = {'commercial': '#237BA5', 'pleasure': '#258EB2', 'marina': '#489F91',
                         'industrial': '#78838A', 'military': '#776482'}[name[5:]]
                    d.ellipse((10, 12, 70, 72), fill=(30,60,75,65))
                    d.ellipse((11, 9, 69, 67), fill=c, outline=white, width=3)
                    d.arc((16,14,64,62),200,290,fill=(255,255,255,110),width=2)
                    if name == 'port-pleasure':
                        d.ellipse((36, 20, 44, 28), outline=white, width=3)
                        d.line((40, 28, 40, 57), fill=white, width=4)
                        d.line((28, 36, 52, 36), fill=white, width=3)
                        d.arc((24, 34, 56, 61), 0, 180, fill=white, width=4)
                    elif name == 'port-commercial':
                        d.polygon([(22, 44), (58, 44), (51, 56), (29, 56)], fill=white)
                        d.rectangle((30, 34, 50, 44), fill=white)
                        d.rectangle((34, 27, 40, 34), fill=white)
                        d.line((20, 59, 60, 59), fill=white, width=2)
                    elif name == 'port-marina':
                        d.line((23, 54, 57, 54), fill=white, width=3)
                        for x in [28, 40, 52]:
                            d.line((x, 27, x, 54), fill=white, width=3)
                            d.line((x, 34, x+5, 34), fill=white, width=3)
                            d.line((x, 43, x+5, 43), fill=white, width=3)
                    elif name == 'port-industrial':
                        d.line((25, 56, 25, 28, 54, 28), fill=white, width=4)
                        d.line((25, 28, 48, 20, 54, 28), fill=white, width=3)
                        d.line((49, 29, 49, 44), fill=white, width=3)
                        d.line((46, 44, 49, 47, 52, 44), fill=white, width=3)
                        d.line((20, 58, 60, 58), fill=white, width=3)
                    else:
                        d.rectangle((28, 39, 53, 56), fill=white)
                        d.rectangle((22, 33, 31, 56), fill=white)
                        d.line((40, 22, 40, 39), fill=white, width=3)
                        d.polygon([(41, 22), (53, 26), (41, 30)], fill=white)
                elif name.startswith('anchor'):
                    c = '#A757AB' if name == 'anchor-ship' else '#258EB2'
                    d.ellipse((13, 15, 67, 69), fill=(244, 251, 255, 65))
                    width = 5 if name == 'anchor-ship' else 4
                    d.ellipse((35, 19, 45, 29), outline=c, width=width)
                    d.line((40, 28, 40, 57), fill=c, width=width)
                    d.line((27, 36, 53, 36), fill=c, width=width)
                    d.arc((21, 34, 59, 62), 0, 180, fill=c, width=width)
                    d.polygon([(22,48),(22,57),(30,54)],fill=c)
                    d.polygon([(58,48),(58,57),(50,54)],fill=c)
                elif name == 'lighthouse':
                    d.polygon([(28, 63), (35, 28), (45, 28), (52, 63)], fill=white, outline=navy, width=3)
                    d.rectangle((33, 40, 47, 47), fill=navy)
                    d.rectangle((38,53,43,63),fill=navy)
                    d.line((29,64,51,64),fill=navy,width=3)
                    d.polygon([(31,23),(40,15),(49,23)],fill=navy)
                    d.rectangle((36, 19, 44, 24), fill=white, outline=navy, width=2)
                    d.rectangle((31, 24, 49, 30), fill=navy)
                    d.line((23, 20, 15, 15), fill=navy, width=3)
                    d.line((57, 20, 65, 15), fill=navy, width=3)
                elif name.startswith('light-'):
                    c = colors[name[6:]]
                    d.polygon([(32, 59), (36, 33), (44, 33), (48, 59)], fill=c, outline=navy, width=2)
                    d.ellipse((34, 23, 46, 35), fill=c, outline=navy, width=2)
                    for x, y, xx, yy in [(40, 18, 40, 24), (40, 56, 40, 62), (18, 40, 24, 40), (56, 40, 62, 40)]:
                        d.line((x, y, xx, yy), fill=c, width=3)
                elif name == 'wreck':
                    d.line((22,24,58,60),fill=white,width=9)
                    d.line((58,24,22,60),fill=white,width=9)
                    d.polygon([(21,42),(55,37),(58,44),(50,58),(31,59)],fill='#C94D54',outline=white,width=2)
                    d.line((22,24,58,60),fill='#C94D54',width=5)
                    d.line((58,24,22,60),fill='#C94D54',width=5)
                elif name.startswith('landmark'):
                    if name == 'landmark-chimney':
                        d.rectangle((35, 24, 45, 58), fill=navy)
                        d.rectangle((32, 21, 48, 26), fill=navy)
                    elif name == 'landmark-monument':
                        d.rectangle((28, 53, 52, 59), fill=navy)
                        d.rectangle((35, 29, 45, 53), fill=navy)
                        d.polygon([(30, 29), (40, 18), (50, 29)], fill=navy)
                    elif name == 'landmark-pylon':
                        d.line((27, 59, 40, 20, 53, 59), fill=navy, width=3)
                        d.line((33, 41, 47, 52, 29, 52, 46, 41), fill=navy, width=2)
                        d.line((27, 31, 53, 31), fill=navy, width=3)
                    else:
                        d.polygon([(30, 59), (37, 23), (43, 23), (50, 59)], fill=navy)
                elif name == 'danger-rock':
                    d.polygon([(28, 51), (34, 35), (43, 40), (48, 30), (56, 51)], fill=navy)
                    for x, y in [(24, 28), (59, 29), (40, 18)]:
                        d.line((x, y, 40, 39), fill=navy, width=2)
                elif name == 'mooring':
                    d.ellipse((35, 19, 45, 29), outline=navy, width=3)
                    d.line((40, 29, 40, 56), fill=navy, width=3)
                    d.arc((23, 33, 57, 61), 0, 180, fill=navy, width=3)
                    d.line((27, 37, 53, 37), fill=navy, width=3)
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
                    elif shape == 'spar': bd.rectangle((36, 28, 44, 60), fill=255)
                    else: bd.polygon([(32, 32), (48, 32), (53, 58), (27, 58)], fill=255)
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
                    elif name in ('lateral-port', 'lateral-starboard'):
                        d.line((40,27,40,33),fill=navy,width=2)
                        if name == 'lateral-port':
                            d.rectangle((35,19,45,27),fill=c,outline=navy,width=1)
                        else:
                            d.polygon([(40,17),(34,27),(46,27)],fill=c,outline=navy,width=1)
                    elif name == 'special':
                        d.line((33, 18, 47, 30), fill=c, width=4); d.line((47, 18, 33, 30), fill=c, width=4)
                    elif name == 'isolated-danger':
                        band(33, 40, '#20262C'); band(51, 59, '#20262C')
                        for y in [15, 25]: d.ellipse((36, y, 44, y+8), fill='#20262C')
                    elif name == 'safe-water':
                        d.rectangle((37, 33, 43, 56), fill=white); d.ellipse((36, 20, 44, 28), fill=c)
                    d.ellipse((25,57,55,65),fill=navy,outline=white,width=2)
                    # Thin body edge keeps conventional colors intact and readable.
                    edge = body.filter(ImageFilter.MaxFilter(3))
                    edge = ImageChops.subtract(edge, body)
                    outline = Image.new('RGBA',(80,80),navy); outline.putalpha(edge)
                    tile.alpha_composite(outline)
                    d = ImageDraw.Draw(tile)
                    d.line((26, 62, 54, 62), fill=white, width=2)
            tile = tile.resize((size, size), Image.Resampling.LANCZOS)
            x, y = index%8*size, index//8*size
            atlas.paste(tile, (x, y))
            metadata[sprite_name] = {'x': x, 'y': y, 'width': size, 'height': size, 'pixelRatio': ratio}
        suffix = '@2x' if ratio == 2 else ''
        atlas.save(ROOT/f'assets/sprite{suffix}.png')
        (ROOT/f'assets/sprite{suffix}.json').write_text(json.dumps(metadata, indent=2)+'\n')


if __name__ == '__main__':
    rasters()
    data()
    sprites()
    from prepare_relief_masks import demo_mask
    demo_mask()
