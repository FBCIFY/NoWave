"""Génère assets/models/location_puck.glb : flèche de navigation biseautée.

Usage, depuis mobile/ : python3 tool/make_location_puck.py assets/models/location_puck.glb

Repère glTF : X vers la droite, Y vers le haut, la pointe vers -Z.
Ombrage figé dans les couleurs (une teinte par facette) : Mapbox affiche le
puck sans éclairage (model-emissive-strength = 1), sur iOS comme sur Android.
"""
import json
import math
import struct
import sys

# Contour vu de dessus (x, n) avec n vers la pointe, sens trigonométrique.
TIP = (0.0, 1.0)
LEFT = (-0.78, -0.78)
NOTCH = (0.0, -0.36)
RIGHT = (0.78, -0.78)
OUTLINE = [TIP, LEFT, NOTCH, RIGHT]

RIM = 0.11  # largeur du liseré blanc
RIM_HEIGHT = 0.08
EDGE_HEIGHT = 0.16  # bord de la flèche bleue
RIDGE_TIP_HEIGHT = 0.26  # arête centrale, à la pointe
RIDGE_NOTCH_HEIGHT = 0.40  # arête centrale, à l'encoche


def srgb_to_linear(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def color(hex_rgb):
    r, g, b = (int(hex_rgb[i:i + 2], 16) for i in (0, 2, 4))
    return [srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0]


# blue600 de AppColors, éclairé à gauche, dans l'ombre à droite.
MATERIALS = {
    'blue_light': color('3B82F6'),
    'blue_dark': color('1D4ED8'),
    'blue_wall': color('1E3A8A'),
    'rim_top': color('FFFFFF'),
    'rim_wall': color('CBD5E1'),
}


def outward_normals(points):
    normals = []
    for i, (x0, n0) in enumerate(points):
        x1, n1 = points[(i + 1) % len(points)]
        dx, dn = x1 - x0, n1 - n0
        length = math.hypot(dx, dn)
        normals.append((dn / length, -dx / length))
    return normals


def offset(points, distance):
    """Contour décalé vers l'extérieur, angles en onglet."""
    edges = outward_normals(points)
    result = []
    for i, (x, n) in enumerate(points):
        a = edges[i - 1]
        b = edges[i]
        dot = a[0] * b[0] + a[1] * b[1]
        k = distance / (1 + dot)
        result.append((x + (a[0] + b[0]) * k, n + (a[1] + b[1]) * k))
    return result


def to3d(point, height):
    x, n = point
    return (x, height, -n)


def sub(a, b):
    return tuple(p - q for p, q in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def normalize(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


primitives = {name: [] for name in MATERIALS}


def triangle(material, a, b, c, outward):
    """Ajoute un triangle tourné vers [outward] (sens direct vu de dehors)."""
    normal = cross(sub(b, a), sub(c, a))
    if sum(p * q for p, q in zip(normal, outward)) < 0:
        b, c = c, b
        normal = tuple(-p for p in normal)
    normal = normalize(normal)
    primitives[material].append(((a, b, c), normal))


def quad(material, a, b, c, d, outward):
    triangle(material, a, b, c, outward)
    triangle(material, a, c, d, outward)


def walls(material, points, bottom, tops):
    for i, (p, n2d) in enumerate(zip(points, outward_normals(points))):
        q = points[(i + 1) % len(points)]
        outward = (n2d[0], 0.0, -n2d[1])
        quad(
            material,
            to3d(p, bottom),
            to3d(q, bottom),
            to3d(q, tops[(i + 1) % len(points)]),
            to3d(p, tops[i]),
            outward,
        )


up = (0.0, 1.0, 0.0)

# Liseré blanc : une plaque un peu plus grande que la flèche.
rim = offset(OUTLINE, RIM)
rim_tip, rim_left, rim_notch, rim_right = (to3d(p, RIM_HEIGHT) for p in rim)
triangle('rim_top', rim_tip, rim_left, rim_notch, up)
triangle('rim_top', rim_tip, rim_notch, rim_right, up)
walls('rim_wall', rim, 0.0, [RIM_HEIGHT] * 4)

# Flèche bleue posée sur la plaque, avec une arête centrale en relief.
tip = to3d(TIP, RIDGE_TIP_HEIGHT)
notch = to3d(NOTCH, RIDGE_NOTCH_HEIGHT)
left = to3d(LEFT, EDGE_HEIGHT)
right = to3d(RIGHT, EDGE_HEIGHT)
triangle('blue_light', tip, left, notch, up)
triangle('blue_dark', tip, notch, right, up)
walls(
    'blue_wall',
    OUTLINE,
    RIM_HEIGHT,
    [RIDGE_TIP_HEIGHT, EDGE_HEIGHT, RIDGE_NOTCH_HEIGHT, EDGE_HEIGHT],
)

# Une unité de long, centrée sur la position de l'utilisateur.
all_points = [v for tris in primitives.values() for (t, _) in tris for v in t]
min_z = min(v[2] for v in all_points)
max_z = max(v[2] for v in all_points)
scale = 1 / (max_z - min_z)
center_z = (min_z + max_z) / 2


def place(v):
    return (v[0] * scale, v[1] * scale, (v[2] - center_z) * scale)


binary = bytearray()
buffer_views = []
accessors = []
meshes_primitives = []
materials = []

for index, (name, rgba) in enumerate(MATERIALS.items()):
    materials.append({
        'name': name,
        'pbrMetallicRoughness': {
            'baseColorFactor': rgba,
            'metallicFactor': 0.0,
            'roughnessFactor': 0.8,
        },
    })
    tris = primitives[name]
    positions = [place(v) for (t, _) in tris for v in t]
    normals = [n for (_, n) in tris for _ in range(3)]

    attributes = {}
    for attribute, values in (('POSITION', positions), ('NORMAL', normals)):
        offset_bytes = len(binary)
        for value in values:
            binary += struct.pack('<3f', *value)
        buffer_views.append({
            'buffer': 0,
            'byteOffset': offset_bytes,
            'byteLength': len(values) * 12,
            'target': 34962,
        })
        accessor = {
            'bufferView': len(buffer_views) - 1,
            'componentType': 5126,
            'count': len(values),
            'type': 'VEC3',
        }
        if attribute == 'POSITION':
            accessor['min'] = [min(v[i] for v in values) for i in range(3)]
            accessor['max'] = [max(v[i] for v in values) for i in range(3)]
        accessors.append(accessor)
        attributes[attribute] = len(accessors) - 1

    # Mapbox plante (iOS) sur une primitive sans indices : on les écrit même
    # si chaque sommet ne sert qu'une fois.
    offset_bytes = len(binary)
    binary += struct.pack(f'<{len(positions)}H', *range(len(positions)))
    buffer_views.append({
        'buffer': 0,
        'byteOffset': offset_bytes,
        'byteLength': len(positions) * 2,
        'target': 34963,
    })
    binary += b'\0' * (-len(binary) % 4)
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5123,
        'count': len(positions),
        'type': 'SCALAR',
    })

    meshes_primitives.append({
        'attributes': attributes,
        'indices': len(accessors) - 1,
        'material': index,
    })

gltf = {
    'asset': {'version': '2.0', 'generator': 'NoWave make_puck.py'},
    'scene': 0,
    'scenes': [{'nodes': [0]}],
    'nodes': [{'mesh': 0, 'name': 'location_puck'}],
    'meshes': [{'primitives': meshes_primitives}],
    'materials': materials,
    'accessors': accessors,
    'bufferViews': buffer_views,
    'buffers': [{'byteLength': len(binary)}],
}

json_chunk = json.dumps(gltf, separators=(',', ':')).encode()
json_chunk += b' ' * (-len(json_chunk) % 4)
binary += b'\0' * (-len(binary) % 4)
total = 12 + 8 + len(json_chunk) + 8 + len(binary)

with open(sys.argv[1], 'wb') as out:
    out.write(struct.pack('<III', 0x46546C67, 2, total))
    out.write(struct.pack('<II', len(json_chunk), 0x4E4F534A))
    out.write(json_chunk)
    out.write(struct.pack('<II', len(binary), 0x004E4942))
    out.write(binary)

print(f'{total} octets, {sum(len(t) for t in primitives.values())} triangles')
