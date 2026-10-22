import 'dart:convert';
import 'dart:io';

import 'land_colors.dart';
import 'marine/marine_palette.dart';

/// One cartographic native style, from the globe to the harbour.
class GlobeStyle {
  static const waterSource = 'nowave-water-mask';
  static const terrainSource = 'nowave-landcover';
  static const initialZoom = 0.65;
  static const initialLongitude = 15.0;
  static const initialLatitude = 12.0;

  static Future<String> prepare() async {
    final directory = Directory('${Directory.systemTemp.path}/nowave-globe-v2');
    await directory.create(recursive: true);
    final file = File('${directory.path}/style.json');
    await file.writeAsString(jsonEncode(document(directory.uri)));
    return file.uri.toString();
  }

  static Map<String, Object> document(Uri imageDirectory) => {
    'version': 8,
    'name': 'NoWave Earth / marine',
    'center': [initialLongitude, initialLatitude],
    'zoom': initialZoom,
    'bearing': 0,
    'pitch': 0,
    'imports': [
      {
        'id': 'basemap',
        'url': 'mapbox://styles/mapbox/standard',
        'config': MarinePalette.basemapConfig,
      },
    ],
    'projection': {'name': 'globe'},
    'fog': {
      'range': [0.8, 8],
      'color': '#84D6F2',
      'high-color': 'rgba(40, 145, 210, 0.70)',
      // The native halo fades into the fixed Flutter space background.
      'space-color': 'rgba(1, 3, 11, 0)',
      'horizon-blend': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        0.010,
        4,
        0.006,
        7,
        0.003,
      ],
      // Native stars rotate with camera longitude. GlobeStars owns the stable
      // field and preserves the previous zoom-dependent fade behind this map.
      'star-intensity': 0,
    },
    'sources': {
      waterSource: {
        'type': 'vector',
        'url': 'mapbox://mapbox.mapbox-streets-v8',
        'maxzoom': 14,
        'prefetch-zoom-delta': 0,
      },
      terrainSource: {
        'type': 'vector',
        'url': 'mapbox://mapbox.mapbox-terrain-v2',
        'maxzoom': 14,
        'prefetch-zoom-delta': 0,
      },
    },
    'layers': [
      // BOTTOM keeps roads, buildings and labels above real land classes.
      {
        'id': 'nowave-landcover',
        'type': 'fill',
        'source': terrainSource,
        'source-layer': 'landcover',
        'slot': 'bottom',
        'paint': {
          'fill-color': LandColors.between(
            [
              'match',
              ['get', 'class'],
              'wood',
              MarinePalette.forest,
              'scrub',
              MarinePalette.scrub,
              'grass',
              MarinePalette.vegetation,
              'crop',
              MarinePalette.crop,
              'snow',
              MarinePalette.snow,
              'rgba(0,0,0,0)',
            ],
            [
              'match',
              ['get', 'class'],
              'wood',
              LandColors.reduced(MarinePalette.forest),
              'scrub',
              LandColors.reduced(MarinePalette.scrub),
              'grass',
              LandColors.reduced(MarinePalette.vegetation),
              'crop',
              LandColors.reduced(MarinePalette.crop),
              'snow',
              LandColors.reduced(MarinePalette.snow),
              'rgba(0,0,0,0)',
            ],
          ),
          'fill-emissive-strength': 1,
        },
      },
      {
        'id': 'nowave-land-relief',
        'type': 'fill',
        'source': terrainSource,
        'source-layer': 'hillshade',
        'slot': 'bottom',
        'paint': {
          'fill-color': LandColors.between(
            [
              'match',
              ['get', 'class'],
              'shadow',
              '#766344',
              'highlight',
              '#E2CCA0',
              'rgba(0,0,0,0)',
            ],
            [
              'match',
              ['get', 'class'],
              'shadow',
              LandColors.reduced('#766344'),
              'highlight',
              LandColors.reduced('#E2CCA0'),
              'rgba(0,0,0,0)',
            ],
          ),
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            0,
            0.22,
            12,
            0.22,
            16,
            0.0,
          ],
          'fill-emissive-strength': 1,
        },
      },
      // Same fallback at every zoom; known bathymetry draws above it at Z5.
      {
        'id': 'nowave-earth-ocean',
        'type': 'fill',
        'source': waterSource,
        'source-layer': 'water',
        'slot': 'bottom',
        'paint': {
          'fill-color': MarinePalette.water,
          'fill-opacity': 1,
          'fill-emissive-strength': 1,
        },
      },
      for (final disputed in [false, true])
        {
          'id': 'nowave-national-boundaries${disputed ? '-disputed' : ''}',
          'type': 'line',
          'source': waterSource,
          'source-layer': 'admin',
          'slot': 'middle',
          'filter': [
            'all',
            [
              '==',
              ['get', 'admin_level'],
              0,
            ],
            [
              '==',
              ['get', 'maritime'],
              'false',
            ],
            [
              '==',
              ['get', 'disputed'],
              disputed ? 'true' : 'false',
            ],
            [
              'any',
              [
                '==',
                ['get', 'worldview'],
                'all',
              ],
              [
                'in',
                'US',
                ['get', 'worldview'],
              ],
            ],
          ],
          'paint': {
            'line-color': '#F0F0F0',
            'line-opacity': 0.18,
            'line-width': 0.6,
            if (disputed) 'line-dasharray': [2, 2],
          },
        },
    ],
  };

  static bool isDecorativeSource(String? id) => id == terrainSource;
}
