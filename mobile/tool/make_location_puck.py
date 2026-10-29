"""Génère assets/models/location_puck.glb : flèche de navigation façon Waze.

Usage, depuis mobile/ : python3 tool/make_location_puck.py assets/models/location_puck.glb

Une flèche à encoche orange « sunset », au dessus plat cerclé d'un liseré
sombre et au flanc épais blanc, visible quand la carte est inclinée.
Repère glTF : X vers la droite, Y vers le haut, la pointe vers -Z.
Ombrage figé dans les couleurs des sommets (COLOR_0) : Mapbox affiche le
puck sans éclairage (model-emissive-strength = 1), sur iOS comme sur Android.
Les couleurs sont écrites en sRGB, sans conversion linéaire : Mapbox les
affiche telles quelles, et une conversion les assombrissait (orange brun,
flancs caramel).
"""
import json
import math
import struct
import sys

# Contour vu de dessus (x, n) avec n vers la pointe, et rayon de chaque coin.
CORNERS = [
    ((0.0, 1.0), 0.16),  # pointe
    ((-0.86, -0.80), 0.16),  # aile gauche
    ((0.0, -0.36), 0.40),  # encoche, creusée en arc
    ((0.86, -0.80), 0.16),  # aile droite
]
CENTER = (0.0, 0.05)  # tout le contour est visible depuis ce point

HEIGHT = 0.27  # épaisseur totale
BEVEL = 0.06  # arrondi du bord supérieur
BEVEL_STEPS = 4
RIM_WIDTH = 0.035  # liseré sombre au bord du dessus, à arête franche
RINGS = 10  # anneaux du dessus, du bord vers le centre

# Lumière en haut à gauche, vue de dessus (x, n).
LIGHT = (-0.45, -0.30, 0.85)

# Dessus : du rouge-orangé de la base à l'ambre de la pointe (sRGB).
TOP_STOPS = [(0.0, 'B8320A'), (0.45, 'E2470E'), (0.8, 'F97316'), (1.0, 'FDBA4D')]
TOP_RIM = '8A2405'  # liseré sombre au bord du dessus
SIDE_STOPS = [(0.0, 'E6E9EE'), (1.0, 'FFFFFF')]  # flanc, de l'ombre à la lumière
SIDE_FOOT = 'B9C1CC'  # pied du flanc, au ras de la carte


def normalize(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


def dot(a, b):
    return sum(p * q for p, q in zip(a, b))


def sub(a, b):
    return tuple(p - q for p, q in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


LIGHT = normalize(LIGHT)


def rounded_outline():
    """Contour aux coins arrondis, échantillonné finement, sens trigonométrique."""
    arcs = []
    count = len(CORNERS)
    for i, (corner, radius) in enumerate(CORNERS):
        prev = CORNERS[i - 1][0]
        nxt = CORNERS[(i + 1) % count][0]
        u1 = normalize(sub(prev, corner))
        u2 = normalize(sub(nxt, corner))
        half_angle = math.acos(max(-1.0, min(1.0, dot(u1, u2)))) / 2
        along = radius / math.tan(half_angle)
        bisector = normalize(tuple(a + b for a, b in zip(u1, u2)))
        center = tuple(c + b * radius / math.sin(half_angle)
                       for c, b in zip(corner, bisector))
        start = tuple(c + u * along for c, u in zip(corner, u1))
        end = tuple(c + u * along for c, u in zip(corner, u2))
        a0 = math.atan2(start[1] - center[1], start[0] - center[0])
        a1 = math.atan2(end[1] - center[1], end[0] - center[0])
        sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        steps = max(6, int(abs(sweep) * radius / 0.02)) | 1  # impair : milieu exact
        arcs.append([
            (center[0] + radius * math.cos(a0 + sweep * k / steps),
             center[1] + radius * math.sin(a0 + sweep * k / steps))
            for k in range(steps + 1)
        ])
    points = []
    for i, arc in enumerate(arcs):
        points += arc
        start, end = arc[-1], arcs[(i + 1) % count][0]
        steps = max(1, int(math.dist(start, end) / 0.04))
        points += [
            (start[0] + (end[0] - start[0]) * k / steps,
             start[1] + (end[1] - start[1]) * k / steps)
            for k in range(1, steps)
        ]
    return points


OUTLINE = rounded_outline()


def mix(a, b, t):
    return [p + (q - p) * t for p, q in zip(a, b)]


def hex_rgb(code):
    return [int(code[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def gradient(stops, t):
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(hex_rgb(c0), hex_rgb(c1), (t - t0) / (t1 - t0))
    return hex_rgb(stops[-1][1])


positions, normals, colors, indices = [], [], [], []


def vertex(x, n, height, normal, rgb):
    """Sommet en (x, n, hauteur), normale en (x, n, hauteur), couleur sRGB."""
    positions.append((x, height, -n))
    normals.append((normal[0], normal[2], -normal[1]))
    colors.append(list(rgb) + [1.0])
    return len(positions) - 1


def strip(ring_a, ring_b):
    """Relie deux anneaux de même taille, faces tournées vers leurs normales."""
    count = len(ring_a)
    for i in range(count):
        j = (i + 1) % count
        for tri in ((ring_a[i], ring_a[j], ring_b[j]), (ring_a[i], ring_b[j], ring_b[i])):
            add_triangle(*tri)


def add_triangle(a, b, c):
    face = cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]))
    if dot(face, face) < 1e-14:
        return
    average = tuple(sum(normals[v][k] for v in (a, b, c)) for k in range(3))
    if dot(face, average) < 0:
        b, c = c, b
    indices.extend((a, b, c))


outward = []
for i, (x, n) in enumerate(OUTLINE):
    px, pn = OUTLINE[i - 1]
    nx, nn = OUTLINE[(i + 1) % len(OUTLINE)]
    outward.append(normalize((nn - pn, -(nx - px))))


def side_color(o, t):
    """Flanc plus clair face à la lumière, assombri au ras de la carte."""
    lit = 0.5 + 0.5 * dot((o[0], o[1], 0.0), LIGHT) / 0.55
    rgb = gradient(SIDE_STOPS, lit)
    return mix(hex_rgb(SIDE_FOOT), rgb, t / 0.18) if t < 0.18 else rgb


def top_color(n):
    return gradient(TOP_STOPS, 0.35 + 0.45 * (n + 0.8) / 1.8)


# Flanc : anneaux du sol au début de l'arrondi.
side_rings = []
for t in (0.0, 0.12, 0.25, 1.0):
    side_rings.append([
        vertex(x, n, (HEIGHT - BEVEL) * t, (o[0], o[1], 0.0), side_color(o, t))
        for (x, n), o in zip(OUTLINE, outward)
    ])
for lower, upper in zip(side_rings, side_rings[1:]):
    strip(lower, upper)

# Arrondi du bord supérieur, blanc jusqu'au liseré du dessus.
bevel_rings = [side_rings[-1]]
for k in range(1, BEVEL_STEPS + 1):
    phi = math.pi / 2 * k / BEVEL_STEPS
    inset = BEVEL * (1 - math.cos(phi))
    height = HEIGHT - BEVEL + BEVEL * math.sin(phi)
    bevel_rings.append([
        vertex(x - o[0] * inset, n - o[1] * inset, height,
               normalize((o[0] * math.cos(phi), o[1] * math.cos(phi), math.sin(phi))),
               mix(side_color(o, 1.0), hex_rgb('FFFFFF'), k / BEVEL_STEPS))
        for (x, n), o in zip(OUTLINE, outward)
    ])
for outer, inner in zip(bevel_rings, bevel_rings[1:]):
    strip(outer, inner)

# Dessus plat : un liseré sombre, puis des anneaux resserrés vers le centre.
# Chaque bord de couleur a ses propres sommets : l'arête reste nette au lieu
# d'un dégradé étiré sur tout un triangle.
inner_outline = [(x - o[0] * BEVEL, n - o[1] * BEVEL) for (x, n), o in zip(OUTLINE, outward)]
rim_outline = [(x - o[0] * RIM_WIDTH, n - o[1] * RIM_WIDTH)
               for (x, n), o in zip(inner_outline, outward)]
up = (0.0, 0.0, 1.0)
rim_rings = [
    [vertex(*p, HEIGHT, up, hex_rgb(TOP_RIM)) for p in outline]
    for outline in (inner_outline, rim_outline)
]
top_rings = []
for k in range(RINGS):
    t = 1 - k / RINGS
    top_rings.append([
        vertex(*p, HEIGHT, up, top_color(p[1]))
        for p in ((CENTER[0] + (x - CENTER[0]) * t, CENTER[1] + (n - CENTER[1]) * t)
                  for x, n in rim_outline)
    ])
strip(rim_rings[0], rim_rings[1])
for outer, inner in zip(top_rings, top_rings[1:]):
    strip(outer, inner)
apex = vertex(*CENTER, HEIGHT, up, top_color(CENTER[1]))
for i in range(len(OUTLINE)):
    add_triangle(top_rings[-1][i], top_rings[-1][(i + 1) % len(OUTLINE)], apex)

# Une unité de long, centrée sur la position de l'utilisateur.
min_z = min(v[2] for v in positions)
max_z = max(v[2] for v in positions)
scale = 1 / (max_z - min_z)
center_z = (min_z + max_z) / 2
positions = [(x * scale, y * scale, (z - center_z) * scale) for x, y, z in positions]

binary = bytearray()
buffer_views = []
accessors = []


def add_accessor(fmt, values, accessor_type, component_type, target, bounds=False):
    offset = len(binary)
    for value in values:
        binary.extend(struct.pack(fmt, *value) if isinstance(value, (tuple, list))
                      else struct.pack(fmt, value))
    buffer_views.append({
        'buffer': 0,
        'byteOffset': offset,
        'byteLength': len(binary) - offset,
        'target': target,
    })
    binary.extend(b'\0' * (-len(binary) % 4))
    accessor = {
        'bufferView': len(buffer_views) - 1,
        'componentType': component_type,
        'count': len(values),
        'type': accessor_type,
    }
    if bounds:
        accessor['min'] = [min(v[i] for v in values) for i in range(3)]
        accessor['max'] = [max(v[i] for v in values) for i in range(3)]
    accessors.append(accessor)
    return len(accessors) - 1


attributes = {
    'POSITION': add_accessor('<3f', positions, 'VEC3', 5126, 34962, bounds=True),
    'NORMAL': add_accessor('<3f', normals, 'VEC3', 5126, 34962),
    'COLOR_0': add_accessor('<4f', colors, 'VEC4', 5126, 34962),
}
# Mapbox plante (iOS) sur une primitive sans indices.
index_accessor = add_accessor('<H', indices, 'SCALAR', 5123, 34963)

gltf = {
    'asset': {'version': '2.0', 'generator': 'NoWave make_location_puck.py'},
    'scene': 0,
    'scenes': [{'nodes': [0]}],
    'nodes': [{'mesh': 0, 'name': 'location_puck'}],
    'meshes': [{'primitives': [{
        'attributes': attributes,
        'indices': index_accessor,
        'material': 0,
    }]}],
    'materials': [{
        'name': 'puck',
        'pbrMetallicRoughness': {
            'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
            'metallicFactor': 0.0,
            'roughnessFactor': 0.8,
        },
    }],
    'accessors': accessors,
    'bufferViews': buffer_views,
    'buffers': [{'byteLength': len(binary)}],
}

json_chunk = json.dumps(gltf, separators=(',', ':')).encode()
json_chunk += b' ' * (-len(json_chunk) % 4)
total = 12 + 8 + len(json_chunk) + 8 + len(binary)

with open(sys.argv[1], 'wb') as out:
    out.write(struct.pack('<III', 0x46546C67, 2, total))
    out.write(struct.pack('<II', len(json_chunk), 0x4E4F534A))
    out.write(json_chunk)
    out.write(struct.pack('<II', len(binary), 0x004E4942))
    out.write(binary)

print(f'{total} octets, {len(positions)} sommets, {len(indices) // 3} triangles')
