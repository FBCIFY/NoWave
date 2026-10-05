"""Génère assets/models/location_puck.glb : flèche de navigation « sticker ».

Usage, depuis mobile/ : python3 tool/make_location_puck.py assets/models/location_puck.glb

Une flèche bleue arrondie et bombée, posée sur un liseré blanc épais.
Repère glTF : X vers la droite, Y vers le haut, la pointe vers -Z.
Ombrage figé dans les couleurs des sommets (COLOR_0) : Mapbox affiche le
puck sans éclairage (model-emissive-strength = 1), sur iOS comme sur Android.
"""
import json
import math
import struct
import sys

# Contour vu de dessus (x, n) avec n vers la pointe, et rayon de chaque coin.
CORNERS = [
    ((0.0, 1.0), 0.13),  # pointe
    ((-0.82, -0.82), 0.13),  # aile gauche
    ((0.0, -0.34), 0.40),  # encoche, creusée en arc
    ((0.82, -0.82), 0.13),  # aile droite
]
CENTER = (0.0, 0.0)  # tout le contour est visible depuis ce point

PLATE_HEIGHT = 0.09  # épaisseur du liseré blanc
RIM = 0.19  # largeur du liseré
BODY_HEIGHT = 0.15  # bombé de la flèche au-dessus du liseré
BODY_FALLOFF = 0.24  # distance au bord où la flèche atteint sa hauteur
RIDGE_HEIGHT = 0.07  # arête douce de la pointe à l'encoche
RIDGE_WIDTH = 0.28

RINGS = 14  # anneaux du corps, du bord vers le centre
RIM_STEPS = 6  # pas de l'arrondi du liseré

# Lumière en haut à gauche, un peu vers la pointe ; on regarde d'en haut.
LIGHT = (-0.45, 0.85, -0.30)
VIEW = (0.0, 1.0, 0.0)

# Dégradé du bleu de AppColors, de l'ombre à la lumière (sRGB).
BODY_STOPS = [(0.0, '1E3A8A'), (0.45, '1D4ED8'), (0.75, '2563EB'), (1.0, '60A5FA')]
RIM_STOPS = [(0.0, 'B6C2D1'), (0.6, 'E2E8F0'), (1.0, 'FFFFFF')]


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
HALF = normalize(tuple(p + q for p, q in zip(LIGHT, VIEW)))


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
        steps = max(4, int(abs(sweep) * radius / 0.03)) | 1  # impair : milieu exact
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
SEGMENTS = list(zip(OUTLINE, OUTLINE[1:] + OUTLINE[:1]))


def distance_to_outline(p):
    best = math.inf
    for a, b in SEGMENTS:
        ab = sub(b, a)
        t = max(0.0, min(1.0, dot(sub(p, a), ab) / dot(ab, ab)))
        best = min(best, math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t)))
    return best


def body_height(p):
    s = min(distance_to_outline(p) / BODY_FALLOFF, 1.0)
    pillow = math.sqrt(1 - (1 - s) ** 2)
    ridge = math.exp(-(p[0] / RIDGE_WIDTH) ** 2) * s
    return PLATE_HEIGHT + BODY_HEIGHT * pillow + RIDGE_HEIGHT * ridge


def body_normal(p, eps=0.004):
    dx = (body_height((p[0] + eps, p[1])) - body_height((p[0] - eps, p[1]))) / (2 * eps)
    dn = (body_height((p[0], p[1] + eps)) - body_height((p[0], p[1] - eps))) / (2 * eps)
    # n est l'opposé de z : la pente en z vaut -dn.
    return normalize((-dx, 1.0, dn))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def gradient(stops, t):
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0)
            break
    rgb0 = [int(c0[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    rgb1 = [int(c1[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [a + (b - a) * k for a, b in zip(rgb0, rgb1)]


def shade(stops, normal, shine):
    light = max(0.0, dot(normal, LIGHT))
    rgb = gradient(stops, light)
    highlight = shine * max(0.0, dot(normal, HALF)) ** 24
    rgb = [c + (1 - c) * highlight for c in rgb]
    return [srgb_to_linear(c) for c in rgb] + [1.0]


positions, normals, colors, indices = [], [], [], []


def vertex(x, n, height, normal, rgba):
    positions.append((x, height, -n))
    normals.append(normal)
    colors.append(rgba)
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


# Corps : anneaux resserrés vers le centre, plus denses près du bord.
rings = []
for k in range(RINGS):
    t = 1 - (k / RINGS) ** 1.6
    ring = []
    for x, n in OUTLINE:
        p = (CENTER[0] + (x - CENTER[0]) * t, CENTER[1] + (n - CENTER[1]) * t)
        normal = body_normal(p)
        ring.append(vertex(*p, body_height(p), normal, shade(BODY_STOPS, normal, 0.55)))
    rings.append(ring)
for outer, inner in zip(rings, rings[1:]):
    strip(outer, inner)
apex = vertex(*CENTER, body_height(CENTER), body_normal(CENTER),
              shade(BODY_STOPS, body_normal(CENTER), 0.55))
for i in range(len(OUTLINE)):
    add_triangle(rings[-1][i], rings[-1][(i + 1) % len(OUTLINE)], apex)

# Liseré : dessus plat sous le bord de la flèche, puis arrondi jusqu'au sol.
outward = []
for i, (x, n) in enumerate(OUTLINE):
    px, pn = OUTLINE[i - 1]
    nx, nn = OUTLINE[(i + 1) % len(OUTLINE)]
    outward.append(normalize((nn - pn, -(nx - px))))
flat = RIM - PLATE_HEIGHT
rim_rings = []
profile = [(0.0, PLATE_HEIGHT, 0.0)] + [
    (flat + PLATE_HEIGHT * math.sin(phi), PLATE_HEIGHT * math.cos(phi), phi)
    for phi in (math.pi / 2 * k / RIM_STEPS for k in range(RIM_STEPS + 1))
]
for spread, height, phi in profile:
    ring = []
    for (x, n), (ox, on) in zip(OUTLINE, outward):
        normal = normalize((ox * math.sin(phi), math.cos(phi), -on * math.sin(phi)))
        ring.append(vertex(x + ox * spread, n + on * spread, height, normal,
                           shade(RIM_STOPS, normal, 0.0)))
    rim_rings.append(ring)
for inner, outer in zip(rim_rings, rim_rings[1:]):
    strip(inner, outer)

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
