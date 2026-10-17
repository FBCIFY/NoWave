import 'dart:convert';

import 'package:blueway/features/map/data/buoy_layer.dart';
import 'package:blueway/features/map/data/fixed_aid_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'buoy_layer_test.dart' show evaluate;

class AidMap extends Fake implements MapboxMap {
  @override
  final AidStyle style = AidStyle();
}

class AidStyle extends Fake implements StyleManager {
  final images = <String>{};
  final layers = <String, Map>{};
  bool reject = false;
  @override
  Future<bool> hasStyleImage(String id) async => images.contains(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> addStyleImage(
    String id,
    double scale,
    MbxImage image,
    bool sdf,
    List<ImageStretches?> x,
    List<ImageStretches?> y,
    ImageContent? content,
  ) async {
    expect(scale, 3);
    final size = id == 'nowave-beacon-neutral'
        ? 12
        : id.startsWith('nowave-light-')
        ? 36
        : 72;
    expect(image.width, size);
    expect(image.height, size);
    expect(image.data.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(images.add(id), isTrue);
  }

  @override
  Future<void> addStyleLayer(String json, LayerPosition? position) async {
    if (reject) throw PlatformException(code: 'style-reload');
    expect(position?.below, BuoyLayer.layerId);
    final value = jsonDecode(json) as Map;
    expect(layers.containsKey(value['id']), isFalse);
    layers[value['id'] as String] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Object? image(Map<String, Object> p) =>
      evaluate(FixedAidLayer.imageExpression(), p);

  test(
    'vraies latérales NOAA B : port vert / starboard rouge, ambigu discret',
    () {
      expect(
        image({
          'type': 'beacon_lateral',
          'category': 'port',
          'color': 'green',
          'navigation_system': 'IALA_B',
        }),
        'nowave-beacon-green',
      );
      expect(
        image({
          'type': 'beacon_lateral',
          'category': 'starboard',
          'color': 'red',
          'navigation_system': 'IALA_B',
        }),
        'nowave-beacon-red',
      );
      expect(
        image({
          'type': 'beacon_lateral',
          'category': 'port',
          'color': 'red',
          'navigation_system': 'IALA_B',
        }),
        'nowave-beacon-neutral',
      );
      expect(
        image({'type': 'beacon_lateral', 'color': 'green'}),
        'nowave-beacon-green',
      );
      expect(image({'type': 'beacon_lateral'}), 'nowave-beacon-neutral');
    },
  );

  test(
    'cardinales, danger, eaux saines, marques spéciales restent qualifiés',
    () {
      for (final (category, color) in [
        ('north', 'black_yellow'),
        ('east', 'black_yellow_black'),
        ('south', 'yellow_black'),
        ('west', 'yellow_black_yellow'),
      ]) {
        expect(
          image({
            'type': 'beacon_cardinal',
            'category': category,
            'color': color,
            'color_pattern': 'horizontal',
          }),
          'nowave-beacon-$category',
        );
        expect(
          image({
            'type': 'beacon_cardinal',
            'category': category,
            'color': color,
          }),
          'nowave-beacon-neutral',
        );
      }
      expect(
        image({
          'type': 'beacon_isolated_danger',
          'color': 'black_red_black',
          'color_pattern': 'horizontal',
        }),
        'nowave-beacon-isolated-danger',
      );
      expect(
        image({
          'type': 'beacon_safe_water',
          'color': 'red_white',
          'color_pattern': 'vertical',
        }),
        'nowave-beacon-safe-water',
      );
      expect(
        image({'type': 'beacon_special_purpose', 'color': 'yellow'}),
        'nowave-beacon-yellow',
      );
    },
  );

  test('phare distinct du feu et couleurs multiples prudentes', () {
    expect(
      image({'type': 'lighthouse', 'light_color': 'red'}),
      'nowave-lighthouse-red',
    );
    expect(
      image({'type': 'light', 'light_color': 'green'}),
      'nowave-light-green',
    );
    expect(
      image({'type': 'light', 'light_color': 'red_white_green'}),
      'nowave-light-default',
    );
    expect(image({'type': 'lighthouse'}), 'nowave-lighthouse-default');
  });

  test('seuils et priorité ne changent pas les bouées', () {
    final layers = FixedAidLayer.layers();
    expect(layers.map((l) => l.minZoom), [13, 14, 11, 13, 12, 10]);
    for (final layer in layers) {
      expect(layer.sourceId, BuoyLayer.sourceId);
      expect(layer.sourceLayer, 'seamark');
      expect(layer.slot, LayerSlot.TOP);
      expect(layer.iconAllowOverlap, isFalse);
      expect(layer.iconIgnorePlacement, isFalse);
      expect(evaluate(layer.filter, {'type': 'buoy_lateral'}), isFalse);
    }
    expect(BuoyLayer.layer().iconSizeExpression!.skip(3), [
      10,
      .6,
      13,
      1.1,
      16,
      1.7,
      18,
      2.0,
    ]);
  });

  test('supports inconnus sous les feux, balises qualifiées au-dessus', () {
    // Convertit != dans le sous-ensemble déjà évalué par les tests de bouées.
    Object adapt(Object value) {
      if (value is! List) return value;
      if (value.first == '!=') {
        return [
          'case',
          ['==', adapt(value[1]), adapt(value[2])],
          false,
          true,
        ];
      }
      return value.map((v) => adapt(v as Object)).toList();
    }

    final layers = FixedAidLayer.layers();
    bool accepts(int index, Map<String, Object> p) =>
        evaluate(adapt(layers[index].filter!), p) == true;
    const unknown = {'type': 'beacon_special_purpose', 'light_color': 'white'};
    expect(accepts(0, unknown), isTrue);
    expect(accepts(3, unknown), isFalse);
    const known = {
      'type': 'beacon_lateral',
      'color': 'green',
      'category': 'port',
      'navigation_system': 'IALA_B',
    };
    expect(accepts(0, known), isFalse);
    expect(accepts(3, known), isTrue);
  });

  testWidgets('images et couches idempotentes, panne retentable et reload', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final map = AidMap();
      final aid = FixedAidLayer();
      await Future.wait([aid.addTo(map), aid.addTo(map)]);
      expect(map.style.images.length, 22);
      expect(map.style.layers.length, 6);
      map.style.images.clear();
      map.style.layers.clear();
      map.style.reject = true;
      await expectLater(aid.addTo(map), throwsA(isA<PlatformException>()));
      map.style.reject = false;
      await aid.addTo(map);
      expect(map.style.images.length, 22);
      expect(map.style.layers.length, 6);
    });
  });
}
