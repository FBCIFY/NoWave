"""Build a vendor-neutral v8 style. Data and style are deliberately separate."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLORS = [(0, '#F4FBFF'), (2, '#F4FBFF'), (5, '#DCEFFA'), (10, '#B9DFF2'),
          (20, '#8FCBE7'), (50, '#5AA9D0'), (100, '#337FAF'), (200, '#1E5D8A'),
          (500, '#123F67'), (1000, '#0C2F50')]


def zoom(*stops):
    return ['interpolate', ['linear'], ['zoom'], *stops]


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
    line('contours', 'contour', '#FFFFFF', 9, .65, .33,
         ['any', ['<', ['get', 'depth_m'], 100], ['>=', ['zoom'], 11]])
    label('contour-labels', 'contour', 11, '#FFFFFF',
          ['concat', ['to-string', ['get', 'depth_m']], ' m'], 'line', size=10)
    layers[-1]['paint']['text-halo-color'] = '#337FAF'
    layers[-1]['paint']['text-halo-width'] = .5
    layer('land', 'fill', 'land', {'fill-color': zoom(10, '#F1EFE9', 17, '#E5E2D9')})
    layers.append({'id': 'land-relief', 'type': 'raster', 'source': 'relief',
                   'paint': {'raster-opacity': zoom(8, 0, 13, .32), 'raster-fade-duration': 0}})
    fill('vegetation', 'vegetation', '#B8C9AE', 10, .22)
    fill('coastal-urban', 'urban', '#D5D0C7', 12, .28)
    fill('foreshore', 'foreshore', '#C6D5D5', 8, .3)
    layer('foreshore-texture', 'fill', 'foreshore', {'fill-pattern': 'foreshore-pattern',
          'fill-opacity': zoom(8, 0, 11, .24)}, minzoom=8)
    line('coast', 'coast', '#A8B0B6', 5, 1, .85)
    line('coastal-major-roads', 'road', '#C4C0B8', 14, 1.1, .4,
         ['all', ['==', ['get', 'coastal'], True],
          ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary']]]])
    fill('basins', 'basin', '#B2DCE9', 10, .8)
    line('breakwaters', 'breakwater', '#82919A', 10, 2.3, .9)
    line('quays', 'quay', '#82919A', 12, 1.8, .9)
    line('pontoons', 'pontoon', '#9AA8AF', 15, 1.3, .8)
    line('bridges', 'bridge', '#A8B0B6', 10, 2.5, .9)
    line('channels', 'channel', '#DCEFFA', 9, 1.1, .4)
    line('port-entrances', 'entrance', '#DCEFFA', 9, 1.5, .6)
    for kind, color, pattern in [('shoal', '#667D8B', 'shoal-pattern'),
                                  ('reef', '#566F7E', 'reef-pattern')]:
        fill(kind+'-tint', kind, color, 11, .09)
        layer(kind+'-texture', 'fill', kind, {'fill-pattern': pattern,
              'fill-opacity': zoom(11, 0, 15, .32)}, minzoom=11)
        label(kind+'-names', kind, 17)
    for kind, color in [('restricted', '#6F6B78'), ('military', '#6F6B78'),
                        ('reserve', '#6FB7A8'), ('windfarm', '#8299A8')]:
        fill(kind+'-area', kind, color, 13, .06)
        line(kind+'-outline', kind, color, 13, .8, .4)
    label('reserve-name', 'reserve', 13, '#57998D')
    # Only validated geometry produced from actual sector bearings/ranges may enter this layer.
    fill('light-sectors', 'light_sector', ['get', 'color'], 15, .12)

    for kind, start, end in [('port', 9, 13), ('lighthouse', 9, 14), ('light', 13, 16),
                             ('buoy', 13, 16), ('beacon', 13, 16), ('anchorage', 10, 14),
                             ('ship_anchorage', 11, 14), ('mooring', 15, 17),
                             ('wreck', 13, 17), ('landmark', 14, 17)]:
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
              {'icon-image': ['get', 'icon'], 'icon-size': zoom(start, .55 if secondary else .65, 18, .8 if secondary else .95),
               'icon-padding': 8, 'symbol-sort-key': ['coalesce', ['get', 'rank'], 10],
               'text-field': ['step', ['zoom'], '', end, field],
               'text-font': ['Open Sans Semibold'], 'text-size': zoom(start, 11, 18, 12),
               'text-offset': [0, 1.6], 'text-anchor': 'top', 'text-padding': 8,
               'text-optional': True}, start, valid)
    for kind, start, size in [('sea_name', 4, 15), ('coastal_city', 7, 11),
                              ('coastal_town', 12, 10), ('bay_name', 9, 13),
                              ('cape_name', 11, 12), ('island_name', 10, 12),
                              ('beach_name', 15, 11), ('cove_name', 15, 11)]:
        label(kind, kind, start, '#E5F3FB' if kind in ('sea_name', 'bay_name') else '#697B86', size=size)
        if kind in ('sea_name', 'bay_name'):
            layers[-1]['paint']['text-halo-color'] = '#337FAF'
            layers[-1]['paint']['text-halo-width'] = .5
        if kind == 'sea_name':
            layers[-1]['paint']['text-opacity'] = zoom(4, 0, 6, .85, 11, .85, 13, 0)
            layers[-1]['paint']['text-halo-color'] = '#123F67'
    return {'version': 8, 'name': 'NoWave · Jour',
            'metadata': {'nowave:data_mode': 'DEMO_FICTIVE', 'nowave:schema': 1},
            'center': [.015, 0], 'zoom': 10.5,
            'glyphs': '{base}/assets/font/{fontstack}/{range}.pbf',
            'sprite': '{base}/assets/sprite', 'transition': {'duration': 350, 'delay': 0},
            'sources': {
                'features': {'type': 'geojson', 'data': '{base}/data/demo.geojson',
                             'attribution': 'NoWave — scène entièrement fictive'},
                'bathymetry': {'type': 'image', 'url': '{base}/assets/demo-bathymetry.png',
                               'coordinates': [[-.3, .3], [.3, .3], [.3, -.3], [-.3, -.3]]},
                'relief': {'type': 'image', 'url': '{base}/assets/demo-relief.png',
                           'coordinates': [[-.3, .3], [.3, .3], [.3, -.3], [-.3, -.3]]}},
            'layers': layers}


if __name__ == '__main__':
    (ROOT / 'style.json').write_text(json.dumps(build(), ensure_ascii=False, indent=2)+'\n')
