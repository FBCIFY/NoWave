"""PBF → complete regional extract → normalized disk-backed feature inventory."""
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import tempfile

from shapely.geometry import shape, box
from shapely.ops import unary_union

from pipeline_io import digest, atomic_json, fingerprint, feature

RELEVANT_KEYS = ('natural', 'landuse', 'leisure', 'harbour', 'waterway',
                 'man_made', 'place', 'highway', 'seamark:type')


# Explicit OSM conventions, IALA A. No characteristic is inferred from colour alone.
# https://wiki.openstreetmap.org/wiki/Seamarks/Buoys (also applies to beacons).
SEAMARK_SCHEMES = {
    ('lateral', 'port'): ('lateral-port', 'red', None, 'cylinder', 'red'),
    ('lateral', 'starboard'): ('lateral-starboard', 'green', None, 'cone, point up', 'green'),
    ('lateral', 'preferred_channel_starboard'): (
        'preferred-channel-starboard', 'red;green;red', 'horizontal', 'cylinder', 'red'),
    ('lateral', 'preferred_channel_port'): (
        'preferred-channel-port', 'green;red;green', 'horizontal', 'cone, point up', 'green'),
    ('cardinal', 'north'): ('cardinal-n', 'black;yellow', 'horizontal', '2 cones up', 'black'),
    ('cardinal', 'east'): ('cardinal-e', 'black;yellow;black', 'horizontal', '2 cones base together', 'black'),
    ('cardinal', 'south'): ('cardinal-s', 'yellow;black', 'horizontal', '2 cones down', 'black'),
    ('cardinal', 'west'): ('cardinal-w', 'yellow;black;yellow', 'horizontal', '2 cones point together', 'black'),
    ('safe_water', None): ('safe-water', 'red;white', 'vertical', 'sphere', 'red'),
    ('isolated_danger', None): ('isolated-danger', 'black;red;black', 'horizontal', '2 spheres', 'black'),
    ('special_purpose', None): ('special', 'yellow', None, 'x-shape', 'yellow'),
}
SEAMARK_SHAPES = {'conical': 'cone', 'can': 'can', 'spherical': 'sphere', 'spar': 'spar', 'pillar': 'pillar'}


def seamark_icon(tags, seamark):
    family = seamark.split('_', 1)[1]
    prefix = 'seamark:' + seamark + ':'
    category = tags.get(prefix + 'category') if family in ('lateral', 'cardinal') else None
    scheme = SEAMARK_SCHEMES.get((family, category))
    if scheme is None or tags.get('seamark:virtual') not in (None, 'no'):
        return None
    icon, colour, pattern, topmark, topmark_colour = scheme
    if tags.get(prefix + 'system') not in (None, 'iala-a'):
        return None
    if tags.get(prefix + 'colour') != colour:
        return None
    actual_pattern = tags.get(prefix + 'colour_pattern')
    if pattern is not None and actual_pattern != pattern:
        return None
    if pattern is None and actual_pattern not in (None, 'horizontal'):
        return None
    form = tags.get(prefix + 'shape')
    # Missing/unsupported physical forms remain audited rather than becoming a can.
    if form not in SEAMARK_SHAPES:
        return None
    if family == 'lateral':
        port_hand = category in ('port', 'preferred_channel_starboard')
        if form == ('conical' if port_hand else 'can') or form == 'spherical':
            return None
    icon += '~' + SEAMARK_SHAPES[form]
    actual_topmark = tags.get('seamark:topmark:shape')
    actual_topmark_colour = tags.get('seamark:topmark:colour')
    if actual_topmark is not None or actual_topmark_colour is not None:
        if actual_topmark != topmark or actual_topmark_colour != topmark_colour:
            return None
        icon += '~topmark'
    return icon


def same_dimension(geometry, original_type):
    """Discard point/line remnants from clipping a line/polygon at a boundary."""
    family = ('Polygon', 'MultiPolygon') if 'Polygon' in original_type else (
        ('LineString', 'MultiLineString') if 'LineString' in original_type else ('Point', 'MultiPoint'))
    if geometry.geom_type in family:
        return geometry
    if geometry.geom_type == 'GeometryCollection':
        return unary_union([same_dimension(part, original_type) for part in geometry.geoms])
    from shapely.geometry import GeometryCollection
    return GeometryCollection()

def extract_pbf(source, bbox, cache):
    """Select intersecting features and retain all referenced ways/nodes locally.

    Area assembly catches polygons enclosing the bbox without a vertex inside it.
    IDs and node coordinates are disk-backed; no national GeoJSON is constructed.
    """
    import osmium
    key = fingerprint({'sha256': digest(source), 'bbox': bbox, 'code': digest(Path(__file__))})
    output = cache / (key + '.osm.pbf')
    stamp = output.with_suffix('.json')
    if output.exists() and stamp.exists() and json.loads(stamp.read_text())['sha256'] == digest(output):
        return output
    extent = box(*bbox)
    factory = osmium.geom.GeoJSONFactory()
    temporary = output.with_name(key + '.tmp.osm.pbf')
    with tempfile.TemporaryDirectory(prefix='extract-', dir=cache) as directory:
        with closing(sqlite3.connect(Path(directory) / 'ids.sqlite')) as ids:
            ids.execute('CREATE TABLE selected (type TEXT, id INTEGER, PRIMARY KEY(type,id))')
            processor = osmium.FileProcessor(str(source)).with_locations(
                'sparse_file_array,' + str(Path(directory) / 'nodes.idx')).with_areas().with_filter(
                    osmium.filter.KeyFilter(*RELEVANT_KEYS))
            for obj in processor:
                tags = dict(obj.tags)
                if obj.is_relation() or not relevant(tags):
                    continue
                try:
                    if obj.is_node():
                        geom = shape(json.loads(factory.create_point(obj)))
                        type_, id_ = 'n', obj.id
                    elif obj.is_way():
                        geom = shape(json.loads(factory.create_linestring(obj)))
                        type_, id_ = 'w', obj.id
                    elif obj.is_area():
                        geom = shape(json.loads(factory.create_multipolygon(obj)))
                        type_, id_ = ('w' if obj.from_way() else 'r'), obj.orig_id()
                    else:
                        continue
                    if geom.intersects(extent):
                        ids.execute('INSERT OR IGNORE INTO selected VALUES (?,?)', (type_, id_))
                except (ValueError, RuntimeError) as error:
                    # A broken extraction must not silently look like complete coverage.
                    raise ValueError(f'OSM geometry extraction failed for {obj.id}: {error}') from error
            ids.commit()
            with osmium.BackReferenceWriter(str(temporary), str(source), overwrite=True,
                                            remove_tags=False, relation_depth=10) as writer:
                # Relations may inherit area tags from an outer way, so they
                # must pass even when the raw relation has no relevant key.
                tagged = osmium.filter.KeyFilter(*RELEVANT_KEYS).enable_for(osmium.osm.NODE | osmium.osm.WAY)
                for obj in osmium.FileProcessor(str(source)).with_filter(tagged):
                    if ids.execute('SELECT 1 FROM selected WHERE type=? AND id=?',
                                   (obj.type_str(), obj.id)).fetchone():
                        writer.add(obj)
    os.replace(temporary, output)
    atomic_json(stamp, {'sha256': digest(output), 'input': key})
    return output


def relevant(tags):
    # Avoid allocating a generator for every OSM object (millions of calls).
    return ('natural' in tags or 'landuse' in tags or 'leisure' in tags or
            'harbour' in tags or 'waterway' in tags or 'man_made' in tags or
            'place' in tags or 'highway' in tags or 'seamark:type' in tags)


def normalize(tags, geom):
    """Conservative explicit mappings. Unknown seamarks stay in the audit table."""
    polygon = geom.geom_type in ('Polygon', 'MultiPolygon')
    seamark = tags.get('seamark:type', '')
    kind, icon, extra = None, None, {}
    if tags.get('natural') == 'coastline':
        return [('coast', geom.boundary if polygon else geom, {})]
    if tags.get('leisure') == 'marina' or seamark == 'harbour' or tags.get('harbour') == 'yes':
        category = tags.get('seamark:harbour:category')
        icon = {'marina': 'port-marina', 'fishing': 'port-commercial', 'commercial': 'port-commercial',
                'military': 'port-military', 'pleasure': 'port-pleasure'}.get(category)
        if tags.get('leisure') == 'marina':
            icon = 'port-marina'
        if icon:
            result = [('port', geom.representative_point(), {'icon': icon})]
            if polygon:
                result.append(('marina_extent', geom, {}))
            return result
        return []
    if tags.get('man_made') in ('pier', 'quay', 'breakwater', 'groyne'):
        kind = {'pier': 'pontoon', 'quay': 'quay', 'breakwater': 'breakwater', 'groyne': 'breakwater'}[tags['man_made']]
        geom = geom.boundary if polygon else geom
    elif seamark in ('light_major', 'light_minor') or tags.get('man_made') == 'lighthouse':
        kind = 'lighthouse' if seamark == 'light_major' or tags.get('man_made') == 'lighthouse' else 'light'
        prefix = 'seamark:light:' if 'seamark:light:colour' in tags else 'seamark:light:1:'
        color = tags.get(prefix + 'colour')
        if kind == 'light' and color not in ('red', 'green', 'yellow', 'white', 'black'):
            return []
        icon = 'lighthouse' if kind == 'lighthouse' else 'light-' + color
        characteristic = [tags.get(prefix + key, '') for key in ('character', 'group', 'colour', 'period')]
        extra['characteristic'] = ' '.join(v for v in characteristic if v)
        geom = geom.representative_point()
    elif seamark.startswith(('buoy_', 'beacon_')):
        icon = seamark_icon(tags, seamark)
        if not icon:
            return []
        kind = 'beacon' if seamark.startswith('beacon_') else 'buoy'
        extra['virtual'] = False
        geom = geom.representative_point()
    elif polygon and (tags.get('landuse') in ('forest', 'grass') or tags.get('natural') in ('wood', 'scrub')):
        kind = 'vegetation'
    elif polygon and tags.get('landuse') in ('residential', 'commercial', 'industrial', 'retail'):
        kind = 'urban'
    elif polygon and tags.get('waterway') == 'dock':
        kind = 'basin'
    elif tags.get('highway') in ('motorway', 'trunk', 'primary') and not polygon and tags.get('tunnel', 'no') == 'no':
        kind, extra = 'road', {'coastal': True, 'class': tags['highway']}
    elif tags.get('place') in ('city', 'town', 'island', 'islet') and tags.get('name'):
        kind = {'city': 'coastal_city', 'town': 'coastal_town', 'island': 'island_name', 'islet': 'island_name'}[tags['place']]
        geom = geom.representative_point()
    elif tags.get('natural') in ('bay', 'cape', 'beach') and tags.get('name'):
        kind = tags['natural'] + '_name'
        geom = geom.representative_point()
    elif seamark in ('mooring', 'wreck', 'rock', 'anchorage'):
        kind, icon = {'mooring': ('mooring', 'mooring'), 'wreck': ('wreck', 'wreck'),
                      'rock': ('danger_rock', 'danger-rock'), 'anchorage': ('anchorage', 'anchor')}[seamark]
        extra['identified'] = True
        geom = geom.representative_point()
    if not kind:
        return []
    if icon:
        extra['icon'] = icon
    return [(kind, geom, extra)]


def ingest(pbf, database, bbox, provenance, cache):
    """Two-pass area assembly, on-disk node locations and deduplication by OSM ID."""
    import osmium
    factory = osmium.geom.GeoJSONFactory()
    extent = box(*bbox)
    key = fingerprint({'pbf': digest(pbf), 'bbox': bbox, 'provenance': provenance, 'code': digest(Path(__file__))})
    stamp = database.with_suffix('.json')
    if database.exists() and stamp.exists():
        record = json.loads(stamp.read_text())
        if record.get('key') == key and record.get('sha256') == digest(database):
            return sqlite3.connect(database)
    database.unlink(missing_ok=True)
    db = sqlite3.connect(database)
    db.execute('CREATE TABLE features (id TEXT, kind TEXT, payload TEXT, PRIMARY KEY(id,kind))')
    db.execute('CREATE TABLE skipped (id TEXT PRIMARY KEY, tags TEXT, reason TEXT)')
    # Sparse file indexes use disk, including for large national source PBFs.
    with tempfile.TemporaryDirectory(prefix='locations-', dir=cache) as location_dir:
        processor = osmium.FileProcessor(str(pbf)).with_locations(
            'sparse_file_array,' + str(Path(location_dir) / 'nodes.idx')).with_areas().with_filter(
                osmium.filter.KeyFilter(*RELEVANT_KEYS))
        for obj in processor:
            tags = dict(obj.tags)
            if not tags or obj.is_relation():
                continue
            if obj.is_area():
                osm_id = ('way/' if obj.from_way() else 'relation/') + str(obj.orig_id())
            else:
                osm_id = ('node/' if obj.is_node() else 'way/') + str(obj.id)
            # Early tag filter avoids constructing geometries for buildings etc.
            if not relevant(tags):
                continue
            try:
                if obj.is_node():
                    geom = shape(json.loads(factory.create_point(obj)))
                elif obj.is_area():
                    geom = shape(json.loads(factory.create_multipolygon(obj)))
                elif obj.is_way():
                    if obj.is_closed() and tags.get('area') != 'no' and tags.get('natural') != 'coastline':
                        continue  # Area callback owns these objects; no outline duplicate.
                    geom = shape(json.loads(factory.create_linestring(obj)))
                else:
                    continue
                if not geom.is_valid:
                    raise ValueError('Invalid OSM geometry')
                if not geom.intersects(extent):
                    continue
                normalized = normalize(tags, geom)
                for kind, geometry, extra in normalized:
                    clipped = same_dimension(geometry.intersection(extent), geometry.geom_type)
                    if clipped.is_empty:
                        continue
                    properties = dict(source='OpenStreetMap', license='ODbL-1.0', osm_id=osm_id,
                        osm_tags=tags, osm_timestamp=str(obj.timestamp) if obj.timestamp.timestamp() else None, osm_version=obj.version,
                        name=tags.get('name', tags.get('seamark:name', '')), **provenance, **extra)
                    payload = json.dumps(feature(kind, clipped, **properties))
                    # Area geometry replaces a way representation of the SAME object only.
                    db.execute('INSERT OR REPLACE INTO features VALUES (?,?,?)', (osm_id, kind, payload))
                if not normalized and any(k.startswith('seamark:') for k in tags):
                    db.execute('INSERT OR REPLACE INTO skipped VALUES (?,?,?)',
                               (osm_id, json.dumps(tags), 'Unsupported or insufficient explicit tags'))
            except (ValueError, RuntimeError) as error:
                db.execute('INSERT OR REPLACE INTO skipped VALUES (?,?,?)', (osm_id, json.dumps(tags), str(error)))
    db.commit()
    atomic_json(stamp, {'key': key, 'sha256': digest(database)})
    return db


def coast_from_inventory(db, scope):
    coast = unary_union([shape(json.loads(row[0])['geometry']) for row in
                        db.execute("SELECT payload FROM features WHERE kind='coast'")])
    coast = same_dimension(coast.intersection(scope), "LineString")
    if coast.is_empty:
        raise ValueError('No real OSM coast in the declared French mainland scope')
    return coast


def features_in_zone(db, useful, land, coast):
    from shapely import prepare
    # Most regional objects are inland. Avoid an expensive polygon intersection
    # for each of them; the prepared predicate leaves retained geometries exact.
    for geometry in (useful, land, coast):
        prepare(geometry)
    for payload, in db.execute('SELECT payload FROM features ORDER BY id,kind'):
        value = json.loads(payload)
        kind = value['properties']['kind']
        geom = shape(value['geometry'])
        original_type = geom.geom_type
        zone = coast if kind == 'coast' else useful
        if not zone.intersects(geom):
            continue
        if not zone.covers(geom):
            geom = geom.intersection(zone)
        if kind in ('vegetation', 'urban') and not land.covers(geom):
            geom = geom.intersection(land)
        geom = same_dimension(geom, original_type)
        if not geom.is_empty:
            yield feature(kind, geom, **{k: v for k, v in value['properties'].items() if k not in ('kind', 'demo')})
