import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/buoy_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

// Small evaluator for the data-only subset used by these expressions. This
// exercises actual tile properties, including missing fields and conflicts.
Object? evaluate(Object? expression, Map<String, Object> properties) {
  if (expression is! List) return expression;
  Object? at(int i) => evaluate(expression[i], properties);
  switch (expression.first) {
    case 'get':
      return properties[expression[1]];
    case 'geometry-type':
      return properties['geometry'] ?? 'Point';
    case '==':
      return at(1) == at(2);
    case 'all':
      return expression.skip(1).every((e) => evaluate(e, properties) == true);
    case 'coalesce':
      return expression
          .skip(1)
          .map((e) => evaluate(e, properties))
          .firstWhere((e) => e != null, orElse: () => null);
    case 'case':
      for (var i = 1; i < expression.length - 1; i += 2) {
        if (at(i) == true) return at(i + 1);
      }
      return evaluate(expression.last, properties);
    case 'match':
      final value = at(1);
      for (var i = 2; i < expression.length - 1; i += 2) {
        final label = expression[i];
        if (label == value || label is List && label.contains(value)) {
          return at(i + 1);
        }
      }
      return evaluate(expression.last, properties);
    default:
      throw UnsupportedError('${expression.first}');
  }
}

class TestMap extends Fake implements MapboxMap {
  @override
  final TestStyle style = TestStyle();
}

class TestStyle extends Fake implements StyleManager {
  final images = <String>{};
  final sources = <String, Object?>{};
  final layers = <String, Object?>{};
  int imageAdds = 0;
  int sourceAdds = 0;
  int layerAdds = 0;
  bool rejectSource = false;

  void reload() {
    images.clear();
    sources.clear();
    layers.clear();
  }

  @override
  Future<bool> hasStyleImage(String id) async => images.contains(id);

  @override
  Future<void> addStyleImage(
    String id,
    double scale,
    MbxImage image,
    bool sdf,
    List<ImageStretches?> stretchX,
    List<ImageStretches?> stretchY,
    ImageContent? content,
  ) async {
    final neutral = id == 'nowave-buoy-neutral';
    expect(scale, neutral ? 18 : 3);
    const size = 72;
    expect(image.width, size);
    expect(image.height, size);
    expect(image.width / scale, neutral ? 4 : 24);
    expect(image.data.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(images.add(id), isTrue);
    imageAdds++;
  }

  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {}

  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (rejectSource) throw PlatformException(code: 'source-unavailable');
    expect(sources.containsKey(id), isFalse);
    sources[id] = jsonDecode(properties);
    sourceAdds++;
  }

  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
    layerAdds++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Object? image(Map<String, Object> properties) =>
      evaluate(BuoyLayer.imageExpression(), properties);
  const neutral = 'nowave-buoy-neutral';

  test('seules les cinq bouées ponctuelles entrent dans la couche', () {
    final filter = BuoyLayer.layer().filter;
    for (final type in [
      'buoy_lateral',
      'buoy_cardinal',
      'buoy_isolated_danger',
      'buoy_safe_water',
      'buoy_special_purpose',
    ]) {
      expect(evaluate(filter, {'type': type}), isTrue);
      expect(evaluate(filter, {'type': type, 'geometry': 'Polygon'}), isFalse);
    }
    for (final type in [
      'beacon_lateral',
      'light_major',
      'light_minor',
      'landmark',
      'sounding',
      'anchorage',
      'harbour',
      'buoy_unknown',
      '',
    ]) {
      expect(evaluate(filter, {'type': type}), isFalse);
    }
    expect(evaluate(filter, {}), isFalse);
  });

  test('IALA A : catégorie prioritaire, contradictions neutres', () {
    expect(
      image({'type': 'buoy_lateral', 'category': 'port', 'color': 'red'}),
      'nowave-buoy-red',
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'starboard',
        'color': 'green',
      }),
      'nowave-buoy-green',
    );
    // Une contradiction exige un système régional connu (ici IALA A).
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'port',
        'color': 'green',
        'navigation_system': 'IALA_A',
      }),
      neutral,
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'starboard',
        'color': 'red',
        'navigation_system': 'IALA_A',
      }),
      neutral,
    );
    expect(
      image({'type': 'buoy_lateral', 'category': 'unknown', 'color': 'red'}),
      neutral,
    );
    expect(image({'type': 'buoy_lateral', 'category': 'port'}), neutral);
    // Réel : beaucoup de latérales ne renseignent que la couleur ; aucune
    // catégorie bâbord/tribord n'est déduite pour autant.
    expect(
      image({'type': 'buoy_lateral', 'color': 'green'}),
      'nowave-buoy-green',
    );
    expect(image({'type': 'buoy_lateral'}), neutral);
  });

  test('IALA B : vraies couleurs NOAA et chenaux préférés inversés', () {
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'port',
        'color': 'green',
        'navigation_system': 'IALA_B',
      }),
      'nowave-buoy-green',
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'starboard',
        'color': 'red',
        'navigation_system': 'IALA_B',
      }),
      'nowave-buoy-red',
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'port',
        'color': 'red',
        'navigation_system': 'IALA_B',
      }),
      neutral,
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'preferred_channel_port',
        'color': 'red_green_red',
        'color_pattern': 'horizontal',
        'navigation_system': 'IALA_B',
      }),
      'nowave-buoy-preferred-starboard',
    );
  });

  test('système inconnu : couleur publiée conservée sans inférer IALA A', () {
    expect(
      image({'type': 'buoy_lateral', 'category': 'port', 'color': 'green'}),
      'nowave-buoy-green',
    );
    expect(
      image({'type': 'buoy_lateral', 'category': 'starboard', 'color': 'red'}),
      'nowave-buoy-red',
    );
  });

  test('cardinales : les quatre quadrants gardent leur ordre de bandes', () {
    const colors = {
      'north': 'black_yellow',
      'east': 'black_yellow_black',
      'south': 'yellow_black',
      'west': 'yellow_black_yellow',
    };
    for (final entry in colors.entries) {
      final properties = <String, Object>{
        'type': 'buoy_cardinal',
        'category': entry.key,
        'color': entry.value,
        'color_pattern': 'horizontal',
      };
      expect(image(properties), 'nowave-buoy-${entry.key}');
      expect(image({...properties, 'color_pattern': 'vertical'}), neutral);
      expect(image({...properties, 'category': 'unknown'}), neutral);
    }
    expect(image({'type': 'buoy_cardinal', 'color': 'black_yellow'}), neutral);
  });

  test('danger, eaux saines, marques spéciales et chenaux préférés', () {
    expect(
      image({
        'type': 'buoy_isolated_danger',
        'color': 'black_red_black',
        'color_pattern': 'horizontal',
      }),
      'nowave-buoy-isolated-danger',
    );
    // Réel : OSM 1420666201, rade de Toulon.
    expect(
      image({
        'type': 'buoy_safe_water',
        'color': 'red_white',
        'color_pattern': 'vertical',
      }),
      'nowave-buoy-safe-water',
    );
    expect(
      image({
        'type': 'buoy_safe_water',
        'color': 'red_white',
        'color_pattern': 'horizontal',
      }),
      neutral,
    );
    expect(
      image({'type': 'buoy_special_purpose', 'color': 'yellow'}),
      'nowave-buoy-yellow',
    );
    expect(image({'type': 'buoy_special_purpose', 'color': 'blue'}), neutral);
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'preferred_channel_port',
        'color': 'green_red_green',
        'color_pattern': 'horizontal',
      }),
      'nowave-buoy-preferred-port',
    );
    expect(
      image({
        'type': 'buoy_lateral',
        'category': 'preferred_channel_starboard',
        'color': 'red_green_red',
        'color_pattern': 'horizontal',
      }),
      'nowave-buoy-preferred-starboard',
    );
    expect(image({}), neutral);
  });

  test('ordre, collision et zoom progressif restent explicites', () {
    final layer = BuoyLayer.layer();
    expect(layer.slot, LayerSlot.TOP);
    expect(layer.sourceLayer, 'seamark');
    expect(layer.minZoom, 10);
    expect(layer.iconSize, isNull);
    final size = layer.iconSizeExpression!;
    expect(size.take(3), [
      'interpolate',
      ['linear'],
      ['zoom'],
    ]);
    // Les mêmes ancres de zoom doublent la taille visuelle (48 points à z18).
    expect(size.skip(3), [10, .60, 13, 1.10, 16, 1.70, 18, 2.0]);
    for (var i = 3; i < size.length; i += 2) {
      final scale = size[i + 1] as num;
      expect(scale, inExclusiveRange(0, 2.01));
      if (i == 3) continue;
      expect(size[i] as num, greaterThan(size[i - 2] as num));
      final previous = size[i - 1] as num;
      expect(scale, greaterThan(previous));
      expect(scale - previous, lessThan(1));
    }
    expect(layer.iconAllowOverlap, isFalse);
    expect(layer.iconIgnorePlacement, isFalse);
    expect(layer.iconPitchAlignment, IconPitchAlignment.VIEWPORT);
  });

  testWidgets('installation concurrente idempotente puis reload du style', (
    tester,
  ) async {
    final map = TestMap();
    final buoy = BuoyLayer(apiBaseUrl: 'https://api.example.com/gateway/');
    await tester.runAsync(() async {
      await Future.wait([buoy.addTo(map), buoy.addTo(map)]);
      await buoy.addTo(map);
      expect(map.style.imageAdds, 12);
      expect(map.style.sourceAdds, 1);
      expect(map.style.layerAdds, 1);
      final source = map.style.sources[BuoyLayer.sourceId] as Map;
      expect(source['tiles'], [
        BuoyLayer.tilesUrl(apiBaseUrl: 'https://api.example.com/gateway/'),
      ]);
      expect(source['url'], isNull);
      expect(source['maxzoom'], 14);
      expect(source['attribution'], contains('Open Waters: Seamap'));
      expect(source['attribution'], contains('OpenStreetMap contributors'));
      expect(
        source['attribution'],
        contains('creativecommons.org/licenses/by/4.0/'),
      );
      map.style.reload();
      await buoy.addTo(map);
      expect(map.style.imageAdds, 24);
      expect(map.style.sourceAdds, 2);
      expect(map.style.layerAdds, 2);
    });
  });

  testWidgets('une installation refusée reste retentable', (tester) async {
    final map = TestMap();
    final buoy = BuoyLayer(apiBaseUrl: 'https://api.example.com/gateway/');
    await tester.runAsync(() async {
      map.style.rejectSource = true;
      await expectLater(buoy.addTo(map), throwsA(isA<PlatformException>()));
      expect(map.style.layers, isEmpty);
      map.style.rejectSource = false;
      await buoy.addTo(map);
      expect(map.style.imageAdds, 12);
      expect(map.style.sourceAdds, 1);
      expect(map.style.layerAdds, 1);
    });
  });

  testWidgets('les variantes livrées sont des PNG décodables à densité 3', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final name in [
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
      ]) {
        final bytes = await rootBundle.load('assets/icons/buoys/$name.png');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        const size = 72;
        expect(frame.image.width, size);
        expect(frame.image.height, size);
        if (name == 'neutral') {
          final data = (await frame.image.toByteData())!.buffer.asUint8List();
          // Le nouveau dessin neutre reste sombre, opaque au centre et
          // transparent aux coins ; sa densité 18 conserve le canevas à 4 px.
          final center = (36 * size + 36) * 4;
          expect(data.sublist(center, center + 4), [13, 13, 13, 255]);
          expect(frame.image.width / 18, 4);
          for (final corner in [
            0,
            size - 1,
            size * (size - 1),
            size * size - 1,
          ]) {
            expect(data[corner * 4 + 3], 0);
          }
        }
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
}
