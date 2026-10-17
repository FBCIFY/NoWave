import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'buoy_layer.dart';

/// Aides fixes sur la source seamark existante, sous les bouées prioritaires.
class FixedAidLayer {
  static const layerIds = [
    'nowave-beacons-unqualified',
    'nowave-lights-local',
    'nowave-lights-major',
    'nowave-beacons-local',
    'nowave-beacons-main',
    'nowave-lighthouses',
  ];
  static const _beacons = [
    'beacon_lateral',
    'beacon_cardinal',
    'beacon_isolated_danger',
    'beacon_safe_water',
    'beacon_special_purpose',
  ];
  static const _variants = [
    'red',
    'green',
    'yellow',
    'north',
    'east',
    'south',
    'west',
    'isolated-danger',
    'safe-water',
    'preferred-port',
    'preferred-starboard',
  ];
  static const _lightColors = ['default', 'red', 'green', 'yellow', 'white'];
  Future<Map<String, Uint8List>>? _images;
  Future<void>? _installing;

  Future<void> addTo(MapboxMap map) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Un échec de style reste retentable.
      }
      return addTo(map);
    }
    final install = _install(map);
    _installing = install;
    try {
      await install;
    } finally {
      _installing = null;
    }
  }

  Future<void> _install(MapboxMap map) async {
    final style = map.style;
    for (final entry in (await (_images ??= _loadImages())).entries) {
      if (await style.hasStyleImage(entry.key)) continue;
      final size = entry.key == 'nowave-beacon-neutral'
          ? 12
          : entry.key.startsWith('nowave-light-')
          ? 36
          : 72;
      await style.addStyleImage(
        entry.key,
        3,
        MbxImage(width: size, height: size, data: entry.value),
        false,
        [],
        [],
        null,
      );
    }
    for (final layer in layers()) {
      if (!await style.styleLayerExists(layer.id)) {
        // Même source et même slot : placement des bouées d'abord, puis
        // phares, balises et feux. Les reports sans slot restent au-dessus.
        await style.addLayerAt(layer, LayerPosition(below: BuoyLayer.layerId));
      }
    }
  }

  Future<Map<String, Uint8List>> _loadImages() async {
    try {
      final names = [
        for (final v in _variants) 'beacon-$v',
        for (final kind in ['lighthouse', 'light'])
          for (final c in _lightColors) '$kind-$c',
      ];
      return {
        for (final n in names)
          'nowave-$n': (await rootBundle.load('assets/icons/fixed-aids/$n.png'))
              .buffer
              .asUint8List(),
        'nowave-beacon-neutral': (await rootBundle.load(
          'assets/icons/buoys/neutral.png',
        )).buffer.asUint8List(),
      };
    } catch (_) {
      _images = null;
      rethrow;
    }
  }

  /// Réutilise exactement les règles IALA/qualification des bouées, avec
  /// les types beacon_* et des dessins fixes distincts ; aucune région déduite.
  static Object _beaconExpression(Object value) => switch (value) {
    String s =>
      s
          .replaceAll('buoy_', 'beacon_')
          .replaceAll('nowave-buoy-', 'nowave-beacon-'),
    List list => list.map((v) => _beaconExpression(v as Object)).toList(),
    _ => value,
  };

  static List<Object> imageExpression() => [
    'match',
    ['get', 'type'],
    'lighthouse',
    _lightImage('lighthouse'),
    'light',
    _lightImage('light'),
    _beaconExpression(BuoyLayer.imageExpression()),
  ];

  static List<Object> _lightImage(String kind) => [
    'match',
    ['get', 'light_color'],
    for (final color in _lightColors.where((c) => c != 'default')) ...[
      color,
      'nowave-$kind-$color',
    ],
    'nowave-$kind-default',
  ];

  static List<SymbolLayer> layers() {
    const range = [
      'coalesce',
      ['get', 'light_range'],
      0,
    ];
    const mainBeacons = ['beacon_cardinal', 'beacon_isolated_danger'];
    final specs = <(double, List<Object>, bool)>[
      (
        13,
        [
          'all',
          [
            'match',
            ['get', 'type'],
            _beacons,
            true,
            false,
          ],
          [
            '==',
            _beaconExpression(BuoyLayer.imageExpression()),
            'nowave-beacon-neutral',
          ],
        ],
        false,
      ),
      (
        14,
        [
          'all',
          [
            '==',
            ['get', 'type'],
            'light',
          ],
          ['<', range, 10],
        ],
        false,
      ),
      (
        11,
        [
          'all',
          [
            '==',
            ['get', 'type'],
            'light',
          ],
          ['>=', range, 10],
        ],
        false,
      ),
      (
        13,
        [
          'all',
          [
            'match',
            ['get', 'type'],
            _beacons,
            true,
            false,
          ],
          [
            'match',
            ['get', 'type'],
            mainBeacons,
            false,
            true,
          ],
        ],
        false,
      ),
      (
        12,
        [
          'match',
          ['get', 'type'],
          mainBeacons,
          true,
          false,
        ],
        false,
      ),
      (
        10,
        [
          '==',
          ['get', 'type'],
          'lighthouse',
        ],
        true,
      ),
    ];
    return [
      for (var i = 0; i < specs.length; i++)
        SymbolLayer(
          id: layerIds[i],
          sourceId: BuoyLayer.sourceId,
          sourceLayer: BuoyLayer.sourceLayer,
          slot: LayerSlot.TOP,
          minZoom: specs[i].$1,
          filter: [
            'all',
            [
              '==',
              ['geometry-type'],
              'Point',
            ],
            specs[i].$2,
            // Un support inconnu ne doit pas masquer son feu qualifié.
            if (i == 3 || i == 4)
              [
                '!=',
                _beaconExpression(BuoyLayer.imageExpression()),
                'nowave-beacon-neutral',
              ],
          ],
          iconImageExpression: imageExpression(),
          iconSizeExpression: specs[i].$3
              ? [
                  'interpolate',
                  ['linear'],
                  ['zoom'],
                  10,
                  .85,
                  13,
                  1.05,
                  16,
                  1.25,
                  18,
                  1.35,
                ]
              : [
                  'interpolate',
                  ['linear'],
                  ['zoom'],
                  11,
                  .65,
                  14,
                  .85,
                  17,
                  1.05,
                  18,
                  1.1,
                ],
          iconAllowOverlap: false,
          iconIgnorePlacement: false,
          iconPadding: 2,
          iconAnchor: IconAnchor.CENTER,
          iconPitchAlignment: IconPitchAlignment.VIEWPORT,
          iconRotationAlignment: IconRotationAlignment.VIEWPORT,
          iconEmissiveStrength: 1,
          symbolSortKeyExpression: [
            '-',
            [
              '*',
              [
                'coalesce',
                ['get', 'source_priority'],
                0,
              ],
              -1000,
            ],
            [
              'coalesce',
              ['get', 'light_range'],
              0,
            ],
          ],
        ),
    ];
  }
}
