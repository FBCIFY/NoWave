import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import 'marine_icon_image.dart';
import 'marine_tiles.dart';

/// Bouées seules, normalisées et fusionnées par le backend NoWave.
/// Symboles graphiques NoWave : assets/icons/buoys, avec règles IALA inchangées.
class BuoyLayer {
  BuoyLayer({String? apiBaseUrl})
    : apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl;

  final String apiBaseUrl;
  static const sourceId = 'nowave-buoys';
  static const layerId = 'nowave-buoy-symbols';
  static String tilesUrl({String? apiBaseUrl}) =>
      MarineTiles.template('seamarks', apiBaseUrl: apiBaseUrl);
  static const sourceLayer = 'seamark';

  static const _neutral = 'nowave-buoy-neutral';
  static const _variants = [
    'neutral',
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

  Future<Map<String, MbxImage>>? _images;
  Future<void>? _installing;

  /// Une installation à la fois ; les vérifications visent le style courant,
  /// jamais un booléen conservé après un reload. Une erreur reste retentable.
  Future<void> addTo(MapboxMap map) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // La nouvelle demande peut viser un style rechargé entre-temps.
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
    final images = await (_images ??= _loadImages());
    for (final entry in images.entries) {
      if (await style.hasStyleImage(entry.key)) continue;
      // Le PNG neutre passe de 12 à 72 px : 72/18 conserve son canevas de
      // 4 px logiques. Les onze symboles qualifiés restent à densité 3.
      final scale = entry.key == _neutral ? 18.0 : 3.0;
      await style.addStyleImage(
        entry.key,
        scale,
        entry.value,
        false,
        [],
        [],
        null,
      );
    }
    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        VectorSource(
          id: sourceId,
          tiles: [tilesUrl(apiBaseUrl: apiBaseUrl)],
          // Les cinq types de bouées sont affichés dès z10, overzoom après z14.
          minzoom: 10,
          maxzoom: 14,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.25,
          attribution: MarineTiles.attribution(apiBaseUrl: apiBaseUrl),
        ),
      );
    }
    if (!await style.styleLayerExists(layerId)) {
      await style.addLayer(layer());
    }
  }

  Future<Map<String, MbxImage>> _loadImages() async {
    try {
      return {
        for (final variant in _variants)
          'nowave-buoy-$variant': await MarineIconImage.load(
            'assets/icons/buoys/$variant.png',
          ),
      };
    } catch (_) {
      _images = null;
      rethrow;
    }
  }

  static SymbolLayer layer() => SymbolLayer(
    id: layerId,
    sourceId: sourceId,
    sourceLayer: sourceLayer,
    // Au-dessus des ports (MIDDLE), sous les reports sans slot. Le slot
    // explicite rend cet ordre indépendant de leurs installations asynchrones.
    slot: LayerSlot.TOP,
    minZoom: 10,
    filter: const [
      'all',
      [
        '==',
        ['geometry-type'],
        'Point',
      ],
      [
        'match',
        ['get', 'type'],
        [
          'buoy_lateral',
          'buoy_cardinal',
          'buoy_isolated_danger',
          'buoy_safe_water',
          'buoy_special_purpose',
        ],
        true,
        false,
      ],
    ],
    iconImageExpression: imageExpression(),
    iconSizeExpression: const [
      'interpolate',
      ['linear'],
      ['zoom'],
      10,
      0.60,
      13,
      1.10,
      16,
      1.70,
      18,
      2.0,
    ],
    iconAllowOverlap: false,
    // Participe aux collisions, y compris entre bouées. Les reports gardent
    // leur overlap existant et restent prioritaires. Pas de sous-échantillonnage
    // local ; seules les collisions écran peuvent masquer un symbole.
    iconIgnorePlacement: false,
    iconPadding: 1,
    iconAnchor: IconAnchor.CENTER,
    iconPitchAlignment: IconPitchAlignment.VIEWPORT,
    iconRotationAlignment: IconRotationAlignment.VIEWPORT,
    iconEmissiveStrength: 1,
    symbolSortKeyExpression: const [
      'match',
      ['get', 'type'],
      'buoy_isolated_danger',
      0,
      'buoy_cardinal',
      1,
      'buoy_safe_water',
      2,
      'buoy_lateral',
      3,
      4,
    ],
  );

  /// Une couleur renseignée peut être rendue sans inventer un côté. Si le
  /// système IALA A/B est fourni, une contradiction devient neutre. Sans système
  /// connu, la couleur publiée est conservée sans déduire un côté régional.
  static List<Object> imageExpression() => [
    'match',
    ['get', 'type'],
    'buoy_lateral',
    [
      'match',
      [
        'coalesce',
        ['get', 'category'],
        '',
      ],
      'port',
      _lateral('red', 'green'),
      'starboard',
      _lateral('green', 'red'),
      'preferred_channel_port',
      _preferred(
        'green_red_green',
        'preferred-port',
        'red_green_red',
        'preferred-starboard',
      ),
      'preferred_channel_starboard',
      _preferred(
        'red_green_red',
        'preferred-starboard',
        'green_red_green',
        'preferred-port',
      ),
      '',
      [
        'match',
        ['get', 'color'],
        'red',
        'nowave-buoy-red',
        'green',
        'nowave-buoy-green',
        _neutral,
      ],
      _neutral,
    ],
    'buoy_cardinal',
    [
      'match',
      ['get', 'category'],
      'north',
      _pattern('black_yellow', 'horizontal', 'north'),
      'east',
      _pattern('black_yellow_black', 'horizontal', 'east'),
      'south',
      _pattern('yellow_black', 'horizontal', 'south'),
      'west',
      _pattern('yellow_black_yellow', 'horizontal', 'west'),
      _neutral,
    ],
    'buoy_isolated_danger',
    _pattern('black_red_black', 'horizontal', 'isolated-danger'),
    'buoy_safe_water',
    _pattern('red_white', 'vertical', 'safe-water'),
    'buoy_special_purpose',
    _colored('yellow', 'yellow'),
    _neutral,
  ];

  static List<Object> _lateral(String regionA, String regionB) => [
    'match',
    [
      'coalesce',
      ['get', 'navigation_system'],
      '',
    ],
    'IALA_B',
    _colored(regionB, regionB),
    'IALA_A',
    _colored(regionA, regionA),
    [
      'match',
      ['get', 'color'],
      'red',
      'nowave-buoy-red',
      'green',
      'nowave-buoy-green',
      _neutral,
    ],
  ];

  static List<Object> _preferred(
    String colorA,
    String variantA,
    String colorB,
    String variantB,
  ) => [
    'match',
    [
      'coalesce',
      ['get', 'navigation_system'],
      '',
    ],
    'IALA_B',
    _pattern(colorB, 'horizontal', variantB),
    'IALA_A',
    _pattern(colorA, 'horizontal', variantA),
    [
      'match',
      ['get', 'color'],
      colorA,
      _pattern(colorA, 'horizontal', variantA),
      colorB,
      _pattern(colorB, 'horizontal', variantB),
      _neutral,
    ],
  ];

  static List<Object> _colored(String color, String variant) => [
    'case',
    [
      '==',
      ['get', 'color'],
      color,
    ],
    'nowave-buoy-$variant',
    _neutral,
  ];

  static List<Object> _pattern(String color, String pattern, String variant) =>
      [
        'case',
        [
          'all',
          [
            '==',
            ['get', 'color'],
            color,
          ],
          [
            '==',
            ['get', 'color_pattern'],
            pattern,
          ],
        ],
        'nowave-buoy-$variant',
        _neutral,
      ];
}
