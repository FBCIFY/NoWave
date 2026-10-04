"""Small, deterministic disk primitives shared by the regional pipeline."""
import hashlib
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import tempfile
import uuid


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n')
    os.replace(temp, path)


def feature(kind, geom, **properties):
    from shapely.geometry import mapping
    return {'type': 'Feature', 'geometry': mapping(geom),
            'properties': {'kind': kind, 'demo': False, **properties}}


def geometry_file(path):
    from shapely.geometry import shape
    from shapely.ops import unary_union
    if Path(path).stat().st_size > 128 * 1024 * 1024:
        raise ValueError('Geometry inputs must be regionally clipped (maximum 128 MiB)')
    data = json.loads(Path(path).read_text())
    features = data['features'] if data['type'] == 'FeatureCollection' else [data]
    geom = unary_union([shape(f.get('geometry', f)) for f in features])
    if not geom.is_empty and not (-180 <= geom.bounds[0] <= geom.bounds[2] <= 180
                                  and -85.05112878 <= geom.bounds[1] <= geom.bounds[3] <= 85.05112878):
        raise ValueError(f'Expected WGS84 geometry: {path}')
    if geom.is_empty or not geom.is_valid:
        raise ValueError(f'Empty or invalid geometry: {path}')
    return geom


def checked_asset(spec, base):
    """No implicit downloads or unpinned inputs, including sidecar geometry."""
    for key in ('path', 'sha256', 'source', 'license', 'date'):
        if not spec.get(key):
            raise ValueError(f'Missing asset {key}')
    path = (base / spec['path']).resolve()
    if digest(path) != spec['sha256']:
        raise ValueError(f'SHA256 mismatch: {path}')
    return path


def write_collection(path, features):
    """Stream a GeoJSON collection instead of accumulating regional features."""
    path = Path(path)
    temp = path.with_suffix(path.suffix + '.tmp')
    with temp.open('w') as stream:
        stream.write('{"type":"FeatureCollection","features":[')
        for i, value in enumerate(features):
            if i:
                stream.write(',')
            stream.write(json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False))
        stream.write(']}\n')
    os.replace(temp, path)


GENERATION_FILES = ('coverage.geojson', 'water.geojson', 'features.geojson',
                    'osm-not-rendered.geojson', 'bathymetry.json')


def current_generation(root):
    """Resolve current once, retaining that immutable directory for the whole read.

    Flat layouts remain readable for Cassis and existing pre-generation outputs.
    A broken/escaping current pointer must never fall back to stale flat files.
    """
    root = Path(root).resolve()
    current = root / 'current'
    if current.is_symlink():
        target = current.resolve(strict=True)
        if (target.parent != root / 'generations' or target.name.startswith('.')
                or not target.is_dir()):
            raise ValueError('Invalid current generation pointer')
        return target
    if current.exists() or ((root / 'generations').exists() and not (root / 'manifest.json').is_file()):
        raise ValueError('Missing or invalid current generation pointer')
    return root


@contextmanager
def staged_generation(root):
    """Never write through current; unpublished staging is removed on failure."""
    generations = Path(root) / 'generations'
    if generations.is_symlink():
        raise ValueError('Generation storage must not be a symlink')
    generations.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.staging-', dir=generations))
    try:
        yield staging
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def iter_collection(path, nullable_geometry=False):
    """Read and validate the canonical stream without loading a region into RAM."""
    header = '{"type":"FeatureCollection","features":['
    decoder = json.JSONDecoder()
    with path.open() as stream:
        if stream.read(len(header)) != header:
            raise ValueError(f'Invalid FeatureCollection header: {path}')
        pending, eof, first, need_more = '', False, True, True
        while True:
            if need_more and not eof:
                chunk = stream.read(65536)
                eof = not chunk
                pending += chunk
            pending = pending.lstrip()
            if pending.startswith(']'):
                if (pending[1:] + stream.read()).strip() != '}':
                    raise ValueError(f'Invalid FeatureCollection ending: {path}')
                return
            try:
                start = 0
                if not first:
                    if not pending.startswith(','):
                        raise ValueError('Missing feature separator')
                    start = 1
                    while start < len(pending) and pending[start].isspace():
                        start += 1
                value, end = decoder.raw_decode(pending, start)
            except (ValueError, json.JSONDecodeError):
                if eof:
                    raise ValueError(f'Incomplete FeatureCollection: {path}') from None
                need_more = True
                continue
            if (value.get('type') != 'Feature' or not isinstance(value.get('properties'), dict)
                    or (not nullable_geometry and not isinstance(value.get('geometry'), dict))):
                raise ValueError(f'Invalid feature: {path}')
            # Serialization rejects NaN/Infinity, including in feature properties.
            json.dumps(value, allow_nan=False)
            yield value
            pending, first, need_more = pending[end:], False, False


def validate_collection(path, nullable_geometry=False):
    for _ in iter_collection(path, nullable_geometry):
        pass


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def publish_generation(root, staging, manifest):
    """Validate and seal a generation, then atomically replace its current pointer."""
    root, staging = Path(root), Path(staging)
    if staging.parent.resolve() != (root / 'generations').resolve() or not staging.name.startswith('.staging-'):
        raise ValueError('Expected a staging directory inside this region')
    if set(p.name for p in staging.iterdir()) != set(GENERATION_FILES):
        raise ValueError('Incomplete generation or unexpected staging files')
    geometry_file(staging / 'coverage.geojson')
    geometry_file(staging / 'water.geojson')
    validate_collection(staging / 'features.geojson')
    validate_collection(staging / 'osm-not-rendered.geojson', nullable_geometry=True)
    bathymetry = json.loads((staging / 'bathymetry.json').read_text())
    if bathymetry != manifest['bathymetry']:
        raise ValueError('Inconsistent bathymetry manifest')
    hashes = {name: digest(staging / name) for name in GENERATION_FILES}
    if hashes['features.geojson'] != manifest['features_sha256']:
        raise ValueError('Inconsistent vector digest')
    generation_id = uuid.uuid4().hex
    manifest = {**manifest, 'generation_id': generation_id, 'files_sha256': hashes}
    atomic_json(staging / 'manifest.json', manifest)
    for path in staging.iterdir():
        with path.open('rb') as stream:
            os.fsync(stream.fileno())
    fsync_directory(staging)
    generation = root / 'generations' / generation_id
    os.replace(staging, generation)
    fsync_directory(generation.parent)
    pointer = root / ('.current-' + generation_id)
    try:
        pointer.symlink_to(Path('generations') / generation_id, target_is_directory=True)
        # Commit point: every failure before this replace leaves current intact.
        os.replace(pointer, root / 'current')
        fsync_directory(root)
    finally:
        pointer.unlink(missing_ok=True)
    return manifest
