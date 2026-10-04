"""Bounded-memory, restartable bathymetry mosaic with per-cell source provenance.

Only raster observations inside explicit validity footprints are used. Nearest
sampling preserves source NoData; contours and colour share the resulting field.
"""
from contextlib import ExitStack
import json
import math
import os
from pathlib import Path
from xml.etree import ElementTree as ET

import contourpy
import numpy as np
import rasterio
from rasterio.transform import from_origin
from rasterio.vrt import WarpedVRT
from rasterio.warp import Resampling
from rasterio.windows import Window
from shapely import contains_xy
from shapely.geometry import box, LineString
from shapely.ops import transform

from build_style import COLORS
from coastal_geometry import METRIC_CRS, TO_METRIC, TO_WGS84, polygonal
from pipeline_io import atomic_json, checked_asset, digest, fingerprint, geometry_file, feature


def load_catalog(path):
    catalog = json.loads(path.read_text())
    if catalog.get('schema') != 1 or not catalog.get('vertical_reference'):
        raise ValueError('Catalog schema=1 and vertical_reference are required')
    products = catalog.get('products', [])
    if not products:
        raise ValueError('Declare at least one verified SHOM raster product; unknown coverage is not zero')
    ids = set()
    loaded = []
    for product in products:
        product = dict(product)
        for field in ('id', 'resolution_m', 'vertical_reference', 'positive', 'coverage', 'metadata'):
            if not product.get(field):
                raise ValueError(f'Missing product {field}')
        if product['id'] in ids:
            raise ValueError('Duplicate product id')
        ids.add(product['id'])
        if product['vertical_reference'] != catalog['vertical_reference']:
            raise ValueError('Mixed vertical references require an upstream documented transformation')
        if product['positive'] not in ('up', 'down') or not math.isfinite(product['resolution_m']) or product['resolution_m'] <= 0:
            raise ValueError('Invalid depth sign/resolution')
        product['file'] = checked_asset(product, path.parent)
        product['metadata_file'] = checked_asset(product['metadata'], path.parent)
        product['footprint'] = geometry_file(checked_asset(product['coverage'], path.parent))
        if product['footprint'].geom_type not in ('Polygon', 'MultiPolygon'):
            raise ValueError('Coverage must be a valid polygon in EPSG:4326')
        if product.get('exclude'):
            product['exclusion'] = geometry_file(checked_asset(product['exclude'], path.parent))
            if product['exclusion'].geom_type not in ('Polygon', 'MultiPolygon'):
                raise ValueError('Exclusion must be polygonal')
        with rasterio.open(product['file']) as src:
            if not src.crs or src.count != 1:
                raise ValueError('Each depth raster must have a CRS and exactly one band')
            if src.nodata is None and 'nodata' not in product:
                raise ValueError('Declare NoData explicitly (null only for a fully valid raster)')
        loaded.append(product)
    if len(loaded) > 65535:
        raise ValueError('Too many source products')
    # First valid observation wins. Resolution takes precedence over priority.
    loaded.sort(key=lambda p: (p['resolution_m'], -p.get('priority', 0), p['id']))
    return catalog, loaded


def rgba_from_depth(depth):
    rgba = np.zeros((4, *depth.shape), dtype='float32')
    valid = np.isfinite(depth)
    stops = [d for d, _ in COLORS]
    for channel, offset in enumerate((1, 3, 5)):
        colors = [int(color[offset:offset+2], 16) for _, color in COLORS]
        rgba[channel, valid] = np.interp(depth[valid], stops, colors)
    rgba[3, valid] = 255
    return rgba


def write_raster(path, values, affine, nodata=None):
    temporary = path.with_suffix('.tmp.tif')
    with rasterio.open(temporary, 'w', driver='GTiff', width=values.shape[2], height=values.shape[1],
            count=values.shape[0], dtype=values.dtype, crs=METRIC_CRS, transform=affine,
            nodata=nodata, tiled=True, blockxsize=256, blockysize=256, compress='deflate') as dst:
        dst.write(values)
    os.replace(temporary, path)


def make_vrt(path, blocks, width, height, affine, bands, nodata=None):
    """Sparse virtual mosaic: absent blocks read as NoData, no rectangle allocation."""
    root = ET.Element('VRTDataset', rasterXSize=str(width), rasterYSize=str(height))
    ET.SubElement(root, 'SRS').text = METRIC_CRS
    ET.SubElement(root, 'GeoTransform').text = ','.join(map(str, affine.to_gdal()))
    for band in range(1, bands + 1):
        elem = ET.SubElement(root, 'VRTRasterBand', dataType='Float32', band=str(band))
        if nodata is not None:
            ET.SubElement(elem, 'NoDataValue').text = str(nodata)
        for block in blocks:
            source = ET.SubElement(elem, 'SimpleSource')
            ET.SubElement(source, 'SourceFilename', relativeToVRT='1').text = block['file']
            ET.SubElement(source, 'SourceBand').text = str(band)
            size = block['size']
            ET.SubElement(source, 'SrcRect', xOff='0', yOff='0', xSize=str(size), ySize=str(size))
            ET.SubElement(source, 'DstRect', xOff=str(block['col']), yOff=str(block['row']), xSize=str(size), ySize=str(size))
    temporary = path.with_suffix('.tmp')
    ET.ElementTree(root).write(temporary, encoding='utf-8', xml_declaration=True)
    os.replace(temporary, path)


def build_field(catalog_path, sea_path, output, resolution=100, block_size=512):
    if not math.isfinite(resolution) or resolution <= 0 or not 16 <= block_size <= 2048:
        raise ValueError('Positive resolution and block_size 16..2048 required')
    catalog, products = load_catalog(catalog_path)
    sea = transform(TO_METRIC, geometry_file(sea_path))
    xmin, ymin, xmax, ymax = sea.bounds
    span = resolution * block_size
    left, top = math.floor(xmin / span) * span, math.ceil(ymax / span) * span
    cols = math.ceil((xmax - left) / span)
    rows = math.ceil((top - ymin) / span)
    width, height = cols * block_size, rows * block_size
    affine = from_origin(left, top, resolution, resolution)
    signature = fingerprint({'catalog': catalog, 'sea': digest(sea_path), 'resolution': resolution,
                             'block_size': block_size, 'algorithm': 1,
                             'code': [digest(Path(__file__)), digest(Path(__file__).with_name('build_style.py'))],
                             'rasterio': rasterio.__version__})
    # A changed input gets a distinct generation. Old valid outputs stay readable.
    generation = output / signature
    generation.mkdir(parents=True, exist_ok=True)
    blocks, reused = [], 0
    with rasterio.Env(GDAL_CACHEMAX=64 * 1024 * 1024), ExitStack() as stack:
        views = []
        for product in products:
            source = stack.enter_context(rasterio.open(product['file']))
            options = dict(crs=METRIC_CRS, transform=affine, width=width, height=height,
                           resampling=Resampling.nearest, nodata=np.nan, dtype='float32', warp_mem_limit=64)
            if 'nodata' in product:
                options['src_nodata'] = product['nodata']
            view = stack.enter_context(WarpedVRT(source, **options))
            valid_geom = product['footprint']
            if product.get('exclusion') is not None:
                valid_geom = valid_geom.difference(product['exclusion'])
            views.append((product, view, polygonal(transform(TO_METRIC, valid_geom).intersection(sea))))
        for row in range(rows):
            for col in range(cols):
                x, y = left + col * span, top - row * span
                extent = box(x, y - span, x + span, y)
                if not sea.intersects(extent):
                    continue
                name = f'{row}-{col}'
                stamp = generation / (name + '.json')
                field_file, color_file = generation / (name + '.tif'), generation / (name + '-rgba.tif')
                valid_cache = False
                if stamp.exists() and field_file.exists() and color_file.exists():
                    record = json.loads(stamp.read_text())
                    valid_cache = (record.get('field_sha256') == digest(field_file)
                                   and record.get('rgba_sha256') == digest(color_file))
                if valid_cache:
                    reused += 1
                else:
                    field = np.full((block_size, block_size), np.nan, dtype='float32')
                    sources = np.zeros(field.shape, dtype='float32')
                    block_affine = from_origin(x, y, resolution, resolution)
                    window = Window(col * block_size, row * block_size, block_size, block_size)
                    xx, yy = np.meshgrid(x + (np.arange(block_size) + .5) * resolution,
                                         y - (np.arange(block_size) + .5) * resolution)
                    for source_id, (product, view, validity) in enumerate(views, 1):
                        if not validity.intersects(extent):
                            continue
                        data = view.read(1, window=window, masked=True).filled(np.nan)
                        if product['positive'] == 'up':
                            data = -data
                        # Strict pixel-centre membership: rasterizing a zero-area shared
                        # boundary could otherwise create spurious valid cells.
                        support = contains_xy(validity, xx, yy)
                        valid = np.isnan(field) & np.isfinite(data) & (data >= 0) & support
                        field[valid] = data[valid]
                        sources[valid] = source_id
                    write_raster(field_file, np.stack([field, sources]), block_affine, np.nan)
                    write_raster(color_file, rgba_from_depth(field), block_affine)
                    record = {'field_sha256': digest(field_file), 'rgba_sha256': digest(color_file),
                              'valid_cells': int(np.isfinite(field).sum()),
                              'source_cells': {str(i): int((sources == i).sum()) for i in range(len(products)+1)}}
                    atomic_json(stamp, record)
                blocks.append({'file': field_file.name, 'rgba': color_file.name, 'col': col * block_size,
                               'row': row * block_size, 'size': block_size, **record})
    make_vrt(generation / 'depth.vrt', blocks, width, height, affine, 2, 'nan')
    make_vrt(generation / 'rgba.vrt', [{**b, 'file': b['rgba']} for b in blocks], width, height, affine, 4)
    manifest = {'schema': 1, 'signature': signature, 'crs': METRIC_CRS, 'resolution_m': resolution,
                'block_size': block_size, 'blocks': blocks, 'valid_cells': sum(b['valid_cells'] for b in blocks),
                'vertical_reference': catalog['vertical_reference'],
                'products': [{**catalog_product, 'source_id': i} for i, catalog_product in enumerate(
                    [{k: v for k, v in p.items() if k not in ('file', 'footprint', 'exclusion', 'metadata_file')} for p in products], 1)],
                'depth_vrt': str((generation / 'depth.vrt').resolve()),
                'rgba_vrt': str((generation / 'rgba.vrt').resolve()),
                'complete_coverage': False, 'sampling': 'nearest valid source cell, no extrapolation'}
    atomic_json(output / 'manifest.json', manifest)
    print(f'Bathymetry: {len(blocks)} blocks, {reused} reused, {manifest["valid_cells"]} valid cells', flush=True)
    return manifest


def contours(manifest, levels=(2, 5, 10, 20, 30, 50, 75, 100, 200, 500, 1000)):
    """One sample halo, contour cells owned by their upper-left block; no seams."""
    products = {p['source_id']: p for p in manifest['products']}
    with rasterio.Env(GDAL_CACHEMAX=64 * 1024 * 1024), rasterio.open(manifest['depth_vrt']) as src:
        for block in manifest['blocks']:
            col, row, size = block['col'], block['row'], block['size']
            # Neighbour samples are read from the SAME mosaic, not independently resampled.
            window = Window(col, row, min(size + 1, src.width - col), min(size + 1, src.height - row))
            field, sources = src.read(window=window)
            x = src.transform.c + (col + np.arange(field.shape[1]) + .5) * src.transform.a
            y = src.transform.f + (row + np.arange(field.shape[0]) + .5) * src.transform.e
            for source_id in np.unique(sources[np.isfinite(sources)]):
                if source_id == 0:
                    continue
                product = products[int(source_id)]
                masked = np.ma.masked_where((sources != source_id) | ~np.isfinite(field), field)
                generator = contourpy.contour_generator(x=x, y=y, z=masked, corner_mask=False)
                for level in levels:
                    for coords in generator.lines(level):
                        line = transform(TO_WGS84, LineString(coords))
                        yield feature('contour', line, depth_m=level, source=product['source'],
                            product_id=product['id'], resolution_m=product['resolution_m'],
                            grid_resolution_m=manifest['resolution_m'], vertical_reference=manifest['vertical_reference'],
                            license=product['license'], date=product['date'], source_sha256=product['sha256'])
