"""Build a vendor-neutral v8 style. Data and style are deliberately separate."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPZEN_TILES = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'
RELIEF_ATTRIBUTION = ('Terrain: Mapzen/Tilezen · AWS Open Data · EU-DEM/Copernicus · USGS · NOAA · '
    '<a href="{base}/assets/mapzen-attribution.html">Terrain data credits</a>')


def relief_source(tiles=MAPZEN_TILES, attribution=RELIEF_ATTRIBUTION):
    return {'type': 'raster-dem', 'tiles': [tiles], 'tileSize': 256,
            'encoding': 'terrarium', 'maxzoom': 15, 'attribution': attribution}


COLORS = [(0, '#F4FBFF'), (2, '#F4FBFF'), (5, '#DCEFFA'), (10, '#B9DFF2'),
          (20, '#8FCBE7'), (50, '#5AA9D0'), (100, '#337FAF'), (200, '#1E5D8A'),
          (500, '#123F67'), (1000, '#0C2F50')]


def zoom(*stops):
    return ['interpolate', ['linear'], ['zoom'], *stops]


def outside_mask(coordinates):
    return {'type': 'Feature', 'properties': {}, 'geometry': {'type': 'Polygon',
            'coordinates': [[[-180, -85.051129], [180, -85.051129], [180, 85.051129],
                             [-180, 85.051129], [-180, -85.051129]],
                            coordinates+[coordinates[0]]]}}


def build():
    layers = [{'id': 'sea', 'type': 'background', 'paint': {'background-color': '#0C2F50'}},
              {'id': 'bathymetry', 'type': 'raster', 'source': 'bathymetry',
               'paint': {'raster-opacity': 1, 'raster-fade-duration': 0}}]

    def layer(id_, type_, kind, paint, layout=None, minzoom=0, extra=None):
        value = {'id': id_, 'type': type_, 'source': 'features', 'minzoom': minzoom,
                 'filter': ['==', ['get', 'kind'], kind], 'paint': paint}
        if extra:
            value['filter'] = ['all', value['filter'], extra]
        if layout:
            value['layout'] = layout
        layers.append(value)

    def fill(id_, kind, color, start=8, opacity=.4, extra=None):
        layer(id_, 'fill', kind, {'fill-color': color,
              'fill-opacity': zoom(start, 0, start+2, opacity)}, minzoom=start, extra=extra)

    def line(id_, kind, color, start=8, width=1, opacity=.5, extra=None):
        layer(id_, 'line', kind, {'line-color': color,
              'line-width': zoom(start, .3, 17, width),
              'line-opacity': zoom(start, 0, start+2, opacity)},
              {'line-cap': 'round', 'line-join': 'round'}, start, extra)

    def label(id_, kind, start, color='#4F7187', field=None, placement='point', extra=None, size=12):
        layer(id_, 'symbol', kind, {'text-color': color,
              'text-opacity': zoom(start, 0, start+1.5, 1),
              'text-halo-color': '#F4FBFF', 'text-halo-width': .8},
              {'text-field': field or ['get', 'name'], 'text-font': ['Open Sans Semibold'],
               'text-size': zoom(start, size, 18, size+1), 'symbol-placement': placement,
               'symbol-spacing': 240, 'text-padding': 10,
               'text-offset': [0, 1.5] if placement == 'point' else [0, 0]}, start, extra)

    # Optional polygon depths for vector datasets; raster is preferred for smooth gradients.
    fill('depth-polygons', 'depth_area', ['interpolate', ['linear'], ['get', 'depth_m'],
         *[item for pair in COLORS for item in pair]], 0, 1)
    line('contours', 'contour', ['step', ['get', 'depth_m'], '#81AABD', 5, '#EAF7FD'], 6, .72, .34,
         ['any', ['all', ['>=', ['get', 'depth_m'], 100], ['>=', ['zoom'], 7]],
          ['all', ['in', ['get', 'depth_m'], ['literal', [10, 20, 50]]], ['>=', ['zoom'], 9]],
          ['>=', ['zoom'], 13]])
    layers[-1]['paint']['line-opacity'] = zoom(6, 0, 10, .18, 13, .28, 17, .38)
    label('contour-labels', 'contour', 10, '#E5F3FB',
          ['to-string', ['get', 'depth_m']], 'line', size=12)
    layers[-1]['paint']['text-color'] = ['step', ['get', 'depth_m'], '#638A9E', 10, '#EAF7FD']
    layers[-1]['paint']['text-halo-color'] = ['step', ['get', 'depth_m'], '#F4FBFF', 10, '#337FAF']
    layers[-1]['paint']['text-halo-width'] = .8
    layers[-1]['paint']['text-opacity'] = zoom(10, 0, 11, .25, 12, .85, 18, 1)
    layers[-1]['layout']['symbol-spacing'] = 420
    layers[-1]['filter'] = ['all', layers[-1]['filter'], ['any',
        ['in', ['get', 'depth_m'], ['literal', [5, 10, 20, 50, 100, 200, 500, 1000]]],
        ['>=', ['zoom'], 16]]]
    layer('land', 'fill', 'land', {'fill-color': zoom(10, '#F1EFE9', 17, '#E5E2D9')})
    layers.append({'id': 'land-relief', 'type': 'hillshade', 'source': 'relief',
                   'paint': {'hillshade-exaggeration': zoom(7, 0, 10, .15, 14, .2, 18, .22),
                             'hillshade-shadow-color': '#ACADA5',
                             'hillshade-highlight-color': '#F1EFE9',
                             'hillshade-accent-color': '#E5E2D9'}})
    # Hillshade has no polygon clip in native MapLibre. Restore the exact sea
    # pixels over it, with transparent pixels on every land polygon (incl. islets).
    layers.append({'id': 'relief-outside-scene', 'type': 'fill', 'source': 'relief-outside',
                   'paint': {'fill-color': '#0C2F50', 'fill-antialias': False}})
    layers.append({'id': 'relief-sea-mask', 'type': 'raster', 'source': 'relief-sea-mask',
                   'paint': {'raster-opacity': 1, 'raster-fade-duration': 0,
                             'raster-resampling': 'linear'}})
    # The demo island is geographically in the ocean: never present submarine
    # DEM slopes as real terrestrial relief. Its existing opaque land fill covers
    # hillshade. The separate real preview omits this fictitious land layer.
    land = next(l for l in layers if l['id'] == 'land')
    layers.remove(land)
    layers.append(land)
    # Contours remain above the sea overpaint; their data/style are unchanged.
    contours = [l for l in layers if l['id'] in ('contours', 'contour-labels')]
    layers[:] = [l for l in layers if l not in contours] + contours
    fill('vegetation', 'vegetation', '#B8C9AE', 10, .22)
    fill('coastal-urban', 'urban', '#D5D0C7', 12, .28)
    fill('foreshore', 'foreshore', '#C6D5D5', 8, .3)
    layer('foreshore-texture', 'fill', 'foreshore', {'fill-pattern': 'foreshore-pattern',
          'fill-opacity': zoom(8, 0, 11, .24)}, minzoom=8)
    line('coast', 'coast', '#A8B0B6', 5, 1, .85)
    line('coastal-major-roads', 'road', '#C4C0B8', 14, 1.1, .4,
         ['all', ['==', ['get', 'coastal'], True],
          ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary']]]])
    fill('basins', 'basin', '#B2DCE9', 14, 1)
    line('breakwater-casing', 'breakwater', '#82919A', 12, 10, .95)
    line('breakwaters', 'breakwater', '#E5E2D9', 12, 7, 1)
    line('quays', 'quay', '#6B8794', 14, 2, .9)
    line('pontoon-casing', 'pontoon', '#708C99', 14, 3.5, .9)
    line('pontoons', 'pontoon', '#F4FBFF', 14, 1.8, 1)
    line('bridges', 'bridge', '#A8B0B6', 14, 2.5, .9)
    line('channels', 'channel', '#F4FBFF', 11, 1.1, .55)
    line('port-entrances', 'entrance', '#F4FBFF', 11, 1.5, .7)
    next(l for l in layers if l['id'] == 'channels')['paint']['line-dasharray'] = [5, 4]
    for kind, color, pattern in [('shoal', '#667D8B', 'shoal-pattern'),
                                  ('reef', '#566F7E', 'reef-pattern')]:
        fill(kind+'-tint', kind, color, 11, .035 if kind == 'shoal' else .065)
        layer(kind+'-texture', 'fill', kind, {'fill-pattern': pattern,
              'fill-opacity': zoom(11, 0, 15, .55 if kind == 'reef' else .35)}, minzoom=11)
        label(kind+'-names', kind, 17)
    # Keep submerged textures/isolines below opaque land, including unnamed islets.
    underwater = [l for l in layers if l['id'] in ('contours', 'contour-labels',
        'shoal-tint', 'shoal-texture', 'reef-tint', 'reef-texture')]
    layers[:] = [l for l in layers if l not in underwater]
    index = next(i for i, l in enumerate(layers) if l['id'] == 'land')
    layers[index:index] = underwater
    for kind, color in [('restricted', '#6F6B78'), ('military', '#6F6B78'),
                        ('reserve', '#4DB9A4'), ('windfarm', '#8299A8')]:
        if kind != 'windfarm':
            fill(kind+'-area', kind, color, 11, .14 if kind == 'reserve' else .04)
        line(kind+'-outline', kind, color, 11, 1.1, .8 if kind == 'reserve' else .4)
        layers[-1]['paint']['line-dasharray'] = [5, 3]
        if kind == 'reserve':
            layers[-1]['paint']['line-color'] = '#39958E'
            layers[-1]['paint']['line-width'] = zoom(11, .3, 15, 1.3)
    label('reserve-name', 'reserve', 12, '#DCEFFA', size=14)
    layers[-1]['paint']['text-halo-color'] = '#DCEFFA'
    layers[-1]['paint']['text-color'] = '#366F7B'
    layers[-1]['paint']['text-halo-width'] = .65
    layers[-1]['layout']['text-offset'] = [0, 3]
    layers[-1]['layout']['text-letter-spacing'] = .025
    layers[-1]['layout']['text-line-height'] = 1.3
    # Only validated geometry produced from actual sector bearings/ranges may enter this layer.
    fill('light-sectors', 'light_sector', ['get', 'color'], 15, .12)

    for kind, start, end in [('port', 9, 13), ('lighthouse', 9, 14), ('light', 13, 16),
                             ('buoy', 12.5, 16), ('beacon', 13, 16), ('anchorage', 10, 14),
                             ('ship_anchorage', 11, 14), ('mooring', 14, 17),
                             ('wreck', 11, 17), ('danger_rock', 13, 17), ('landmark', 14, 17)]:
        valid = ['!=', ['get', 'virtual'], True] if kind in ('buoy', 'beacon') else None
        if kind in ('anchorage', 'ship_anchorage'):
            valid = ['==', ['get', 'identified'], True]
        secondary = kind in ('light', 'buoy', 'beacon', 'mooring', 'landmark')
        field = ['concat', ['coalesce', ['get', 'name'], ''], '\n',
                 ['coalesce', ['get', 'characteristic'], '']] if kind in ('lighthouse', 'light', 'buoy', 'beacon') else ['get', 'name']
        layer(kind+'-symbols', 'symbol', kind, {
              'icon-opacity': zoom(start, 0, start+1.5, 1),
              'text-opacity': zoom(end, 0, end+1.5, 1),
              'text-color': '#4F7187', 'text-halo-color': '#F4FBFF', 'text-halo-width': .7},
              {'icon-image': ['get', 'icon'], 'icon-size': zoom(start, .8 if secondary else .85, 18, 1.1 if secondary else 1.25),
               'icon-padding': 4, 'symbol-sort-key': ['coalesce', ['get', 'rank'], 10],
               'text-field': ['step', ['zoom'], '', end, field],
               'text-font': ['Open Sans Semibold'], 'text-size': zoom(start, 11, 18, 12),
               'text-offset': [0, 1.6], 'text-anchor': 'top', 'text-padding': 8,
               'text-optional': True}, start, valid)
        if kind == 'lighthouse':
            layers[-1]['layout']['icon-allow-overlap'] = True
    for kind, start, size in [('sea_name', 4, 15), ('gulf_name', 6, 14), ('roadstead_name', 9, 13), ('coastal_city', 7, 11),
                              ('coastal_town', 12, 10), ('bay_name', 9, 13),
                              ('cape_name', 8, 12), ('island_name', 8, 12),
                              ('beach_name', 15, 11), ('cove_name', 15, 11), ('calanque_name', 15, 11)]:
        label(kind, kind, start, '#E5F3FB' if kind in ('sea_name', 'gulf_name', 'bay_name', 'roadstead_name') else '#697B86', size=size)
        if kind in ('sea_name', 'gulf_name', 'bay_name', 'roadstead_name'):
            layers[-1]['paint']['text-halo-color'] = '#337FAF'
            layers[-1]['paint']['text-halo-width'] = .5
        if kind == 'sea_name':
            layers[-1]['paint']['text-opacity'] = zoom(4, .55, 6, .7, 11, .7, 13, 0)
            layers[-1]['layout']['text-letter-spacing'] = .18
            layers[-1]['layout']['text-size'] = 19
            layers[-1]['layout']['text-offset'] = [0, 0]
            layers[-1]['layout']['text-allow-overlap'] = True
            layers[-1]['paint']['text-halo-color'] = '#123F67'
    return {'version': 8, 'name': 'NoWave · Jour',
            'metadata': {'nowave:data_mode': 'DEMO_FICTIVE', 'nowave:schema': 1, 'nowave:relief_label': 'réel Mapzen/AWS (externe)'},
            'center': [.015, 0], 'zoom': 10.5,
            'glyphs': '{base}/assets/font/{fontstack}/{range}.pbf',
            'sprite': '{base}/assets/sprite', 'transition': {'duration': 350, 'delay': 0},
            'sources': {
                'features': {'type': 'geojson', 'data': '{base}/data/demo.geojson',
                             'attribution': 'NoWave — terre, bathymétrie et objets nautiques fictifs'},
                'bathymetry': {'type': 'image', 'url': '{base}/assets/demo-bathymetry.png',
                               'coordinates': [[-.3, .3], [.3, .3], [.3, -.3], [-.3, -.3]]},
                'relief': relief_source(),
                'relief-sea-mask': {'type': 'image', 'url': '{base}/assets/demo-sea-mask.png',
                    'coordinates': [[-.3, .3], [.3, .3], [.3, -.3], [-.3, -.3]]},
                'relief-outside': {'type': 'geojson', 'data': outside_mask(
                    [[-.3, .3], [.3, .3], [.3, -.3], [-.3, -.3]])}},
            'layers': layers}


REAL_AREA_PROFILES = {
    'cassis': {
        'name': 'NoWave · Cassis réel',
        'manifest': 'data/cassis/manifest.json',
        'features': '{base}/data/cassis/features.geojson',
        'bathymetry': '{base}/assets/cassis-bathymetry.png',
        'water': '{base}/data/cassis/water.geojson',
        'metadata': {
            'nowave:data_mode': 'CASSIS_REAL',
            'nowave:coast_label': 'réelle OSM',
            'nowave:bathymetry_label': 'réelle SHOM : levé 2007–2013 / HOMONIM PBMA',
            'nowave:bathymetry_resolution': 'grille 10 m sur sondes ; HOMONIM ≈111 m au large',
            'nowave:missing_depth_label': 'gris bleu = profondeur indisponible ; aucune extrapolation portuaire',
            'nowave:port_label': 'réels OSM',
            'nowave:navigation_label': 'feux OSM réels ; autres catégories absentes non affichées',
            'nowave:warning': 'Ne pas utiliser NoWave pour la navigation officielle.',
        },
        'features_attribution':
            '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors · ODbL</a>',
        'bathymetry_attribution': (
            ' · <a href="https://doi.org/10.17183/MNT_MED100m_GDL_CA_HOMONIM_WGS84">'
            'Shom, 2015 · HOMONIM PBMA</a>'
            ' · <a href="https://doi.org/10.17183/S201300200">'
            'Shom · levé S201300200 (2007–2013)</a> · Licence Ouverte 2.0'
        ),
    },
}


def build_real_area(profile):
    """Apply the approved NoWave visual style to a real geographic dataset."""
    manifest = json.loads((ROOT/profile['manifest']).read_text())
    style = build()

    style['name'] = profile['name']
    style['metadata'].update(profile['metadata'])
    style['center'], style['zoom'] = manifest['center'], manifest['zoom']

    style['sources'] = {
        'features': {
            'type': 'geojson',
            'data': profile['features'],
            'attribution': profile['features_attribution'],
        },
        'bathymetry': {
            'type': 'image',
            'url': profile['bathymetry'],
            'coordinates': manifest['coordinates'],
        },
        'relief': style['sources']['relief'],
        'relief-sea-mask': {
            'type': 'geojson',
            'data': profile['water'],
        },
        'relief-outside': {
            'type': 'geojson',
            'data': outside_mask(manifest['coordinates']),
        },
    }

    # Image sources do not support attribution in the v8 specification.
    style['sources']['features']['attribution'] += profile['bathymetry_attribution']

    layers = style['layers']

    land = next(l for l in layers if l['id'] == 'land')
    layers.remove(land)
    layers.insert(
        next(i for i, l in enumerate(layers) if l['id'] == 'land-relief'),
        land,
    )

    # A true vector water polygon covers underwater DEM at every zoom.
    mask = next(l for l in layers if l['id'] == 'relief-sea-mask')
    mask['type'] = 'fill'
    mask['paint'] = {
        'fill-color': '#B9CDD7',
        'fill-antialias': False,
    }

    next(
        l for l in layers if l['id'] == 'relief-outside-scene'
    )['paint']['fill-color'] = '#B9CDD7'

    bathymetry = next(l for l in layers if l['id'] == 'bathymetry')

    # Keep linear raster interpolation for smooth nautical rendering while
    # slightly reducing high-zoom contrast on sparse survey data.
    bathymetry['paint']['raster-opacity'] = [
        'interpolate', ['linear'], ['zoom'],
        12, 1.0,
        16, 0.96,
        18, 0.90,
    ]

    layers.remove(bathymetry)
    layers.insert(layers.index(mask) + 1, bathymetry)

    return style


def build_cassis():
    """Backward-compatible Cassis entry point during the national refactor."""
    return build_real_area(REAL_AREA_PROFILES['cassis'])

if __name__ == '__main__':
    (ROOT / 'style.json').write_text(json.dumps(build(), ensure_ascii=False, indent=2)+'\n')
    if (ROOT/'data/cassis/manifest.json').exists():
        (ROOT/'cassis-style.json').write_text(json.dumps(build_cassis(), ensure_ascii=False, indent=2)+'\n')
