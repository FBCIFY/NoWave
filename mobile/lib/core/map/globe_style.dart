import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// One native style, from the globe to the harbour. No style swap on zoom.
class GlobeStyle {
  static const satelliteSource = 'nowave-satellite';
  static const waterSource = 'nowave-water-mask';
  static const creditsSource = 'nowave-globe-credits';
  static const imageNames = ['nw', 'ne', 'sw', 'se'];
  static const initialZoom = 0.65;
  static const initialLongitude = 15.0;
  static const initialLatitude = 12.0;

  /// A private temporary directory gives both native SDKs ordinary file URLs.
  /// Flutter asset paths differ between Android and iOS. Only 4 small PNGs
  /// and a JSON document are copied; no satellite tiles are bundled.
  static Future<String> prepare() async {
    final directory = Directory('${Directory.systemTemp.path}/nowave-globe-v1');
    await directory.create(recursive: true);
    for (final name in imageNames) {
      final data = await rootBundle.load('assets/globe/$name.png');
      await File('${directory.path}/$name.png').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
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
        'config': {'lightPreset': 'day'},
      },
    ],
    'projection': {'name': 'globe'},
    'fog': {
      'range': [0.8, 8],
      'color': '#6BBBD4',
      'high-color': 'rgba(35, 125, 187, 0.65)',
      'space-color': '#01030B',
      'horizon-blend': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        0.008,
        4,
        0.006,
        7,
        0.003,
      ],
      'star-intensity': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        0.65,
        3,
        0.4,
        6,
        0,
      ],
    },
    'sources': {
      satelliteSource: {
        'type': 'raster',
        'url': 'mapbox://mapbox.satellite',
        'tileSize': 256,
        'maxzoom': 7,
        'prefetch-zoom-delta': 0,
      },
      // Shared with WaterTextureLayer: real water polygons, never a full
      // screen blue tint. Its existing installation remains idempotent.
      waterSource: {
        'type': 'vector',
        'url': 'mapbox://mapbox.mapbox-streets-v8',
        'maxzoom': 14,
        'prefetch-zoom-delta': 0,
      },
      // TileJSON replaces a URL source's attribution on native Android.
      // An empty local source preserves NASA credits without touching the
      // provider's own attribution or adding geometry, layers or requests.
      creditsSource: {
        'type': 'geojson',
        'data': {'type': 'FeatureCollection', 'features': <Object>[]},
        'attribution':
            '<a href="https://science.nasa.gov/earth/earth-observatory/">Nuages : NASA/GSFC</a> '
            '<a href="https://svs.gsfc.nasa.gov/4720/">Lune : NASA/SVS/LRO</a>',
      },
      for (var i = 0; i < imageNames.length; i++)
        'nowave-clouds-${imageNames[i]}': {
          'type': 'image',
          'url': imageDirectory.resolve('${imageNames[i]}.png').toString(),
          'coordinates': _coordinates(i),
        },
    },
    'layers': [
      {
        'id': 'nowave-earth-satellite',
        'type': 'raster',
        'source': satelliteSource,
        'slot': 'bottom',
        'maxzoom': 7,
        'paint': {
          'raster-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            4,
            1,
            7,
            0,
          ],
          'raster-fade-duration': 150,
          'raster-emissive-strength': 1,
        },
      },
      {
        'id': 'nowave-earth-ocean',
        'type': 'fill',
        'source': waterSource,
        'source-layer': 'water',
        'slot': 'bottom',
        'maxzoom': 7,
        'paint': {
          'fill-color': '#0A4E87',
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            3,
            0.28,
            7,
            0,
          ],
          'fill-emissive-strength': 1,
        },
      },
      for (final name in imageNames)
        {
          'id': 'nowave-earth-clouds-$name',
          'type': 'raster',
          'source': 'nowave-clouds-$name',
          'slot': 'bottom',
          'maxzoom': 5,
          'paint': {
            'raster-opacity': [
              'interpolate',
              ['linear'],
              ['zoom'],
              1,
              1,
              3,
              0.65,
              5,
              0,
            ],
            'raster-fade-duration': 0,
            'raster-emissive-strength': 1,
          },
        },
    ],
  };

  static List<List<double>> _coordinates(int index) {
    const limit = 85.0511287798066;
    final west = index.isEven ? -180.0 : 0.0;
    final east = west + 180;
    final north = index < 2 ? limit : 0.0;
    final south = index < 2 ? 0.0 : -limit;
    return [
      [west, north],
      [east, north],
      [east, south],
      [west, south],
    ];
  }

  static bool isDecorativeSource(String? id) =>
      id == satelliteSource || (id?.startsWith('nowave-clouds-') ?? false);
}
