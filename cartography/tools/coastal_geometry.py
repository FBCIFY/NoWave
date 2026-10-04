"""Coastal product geometry. Never derive a coast from a clipped land boundary."""
from pyproj import Transformer
from shapely import set_precision, make_valid, segmentize
from shapely.geometry import box
from shapely.ops import transform, unary_union

METRIC_CRS = 'EPSG:2154'  # RGF93 / Lambert-93, mainland France (metres).
TO_METRIC = Transformer.from_crs('EPSG:4326', METRIC_CRS, always_xy=True).transform
TO_WGS84 = Transformer.from_crs(METRIC_CRS, 'EPSG:4326', always_xy=True).transform


def line_buffer(coast, distance, batch_size=32):
    """Union identical line buffers in bounded batches, without simplifying coast.

    GEOS buffering a whole real coastline at once builds a huge intermediate
    intersection graph. Buffering its parts gives the same union of discs.
    """
    parts = [coast] if coast.geom_type == 'LineString' else list(coast.geoms)
    batches = [unary_union([part.buffer(distance) for part in parts[i:i + batch_size]])
               for i in range(0, len(parts), batch_size)]
    return unary_union(batches)


def coastal_zone(coast, land, bbox, sea_buffer_nm=10, land_buffer_m=3000):
    if coast.is_empty or coast.geom_type not in ('LineString', 'MultiLineString'):
        raise ValueError('Real coastline lines required')
    if sea_buffer_nm <= 0 or land_buffer_m < 0:
        raise ValueError('Invalid coastal buffer')
    metric_coast = set_precision(transform(TO_METRIC, coast), .01)
    metric_land = set_precision(transform(TO_METRIC, land), .01)
    extent = set_precision(transform(TO_METRIC, segmentize(box(*bbox), .01)), .01)
    sea = line_buffer(metric_coast, sea_buffer_nm * 1852).difference(metric_land).intersection(extent)
    useful = sea.union(line_buffer(metric_coast, land_buffer_m).intersection(metric_land)).intersection(extent)
    return polygonal(transform(TO_WGS84, sea)), polygonal(transform(TO_WGS84, useful))


def polygonal(geom):
    """Repair projection roundoff only; drop zero-area remnants of boolean cuts."""
    geom = make_valid(geom)
    if geom.geom_type in ('Polygon', 'MultiPolygon'):
        return geom
    return unary_union([polygonal(g) for g in geom.geoms if g.geom_type in
                        ('Polygon', 'MultiPolygon', 'GeometryCollection')])
