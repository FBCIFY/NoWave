import 'dart:convert';

import 'buoy_layer_test.dart' show evaluate, expectMarksFade;

import 'package:blueway/features/map/data/hydrography_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class HydroMap extends Fake implements MapboxMap {
  @override
  final HydroStyle style = HydroStyle();
  final states = <String, bool>{};
  bool failQuery = false;
  List<QueriedRenderedFeature?> rendered = [];
  @override
  Future<Size> getSize() async => Size(width: 360, height: 805);
  @override
  Future<List<QueriedRenderedFeature?>> queryRenderedFeatures(
    RenderedQueryGeometry geometry,
    RenderedQueryOptions options,
  ) async {
    expect(options.layerIds, ['nowave-depth-labels']);
    if (failQuery) throw StateError('native query failure');
    return rendered;
  }

  @override
  Future<void> setFeatureState(
    String sourceId,
    String? sourceLayer,
    String featureId,
    String state,
  ) async {
    expect(sourceId, HydrographyLayer.contourSourceId);
    expect(sourceLayer, 'depth_contour');
    states[featureId] = jsonDecode(state)['label_visible'] as bool;
  }
}

QueriedRenderedFeature placedLabel(int id) => QueriedRenderedFeature(
  queriedFeature: QueriedFeature(
    feature: {'id': id},
    source: HydrographyLayer.contourSourceId,
    sourceLayer: 'depth_contour',
    state: '{}',
  ),
  layers: ['nowave-depth-labels'],
);

class HydroStyle extends Fake implements StyleManager {
  final sources = <String, Map>{};
  final layers = <String, Map>{};
  final images = <String>{};
  bool reject = false;
  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<bool> hasStyleImage(String id) async => images.contains(id);
  @override
  Future<void> setStyleSourceProperty(
    String id,
    String property,
    Object value,
  ) async {
    (sources[id] as Map)[property] = value;
  }

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {
    sources[id]!.addAll(jsonDecode(properties) as Map);
  }

  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (reject) throw PlatformException(code: 'source-error');
    expect(sources.containsKey(id), isFalse);
    sources[id] = jsonDecode(properties) as Map;
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map;
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
  }

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
    expect(scale, 2);
    expect(image.width, 64);
    expect(image.data.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(images.add(id), isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('depth lines persist independently from label placement at every upper zoom', () async {
    final map = HydroMap();
    await HydrographyLayer(apiBaseUrl: 'https://api.example.com/').addTo(map);
    final lines = HydrographyLayer.layers().whereType<LineLayer>().where(
      (l) => l.sourceId == HydrographyLayer.contourSourceId,
    );
    for (final line in lines) {
      expect(line.minZoom, 13);
      expect(line.maxZoom, isNull);
      expect(line.lineOpacity, greaterThan(0));
      expect(line.lineOpacityExpression, isNull);
      expect(jsonEncode(line.filter), isNot(contains('feature-state')));
      expect(jsonEncode(line.filter), isNot(contains('derivation')));
      expect(jsonEncode(line.filter), isNot(contains('depth_label')));
    }
    final labels = map.style.layers['nowave-depth-labels']!;
    expect(labels['minzoom'], 13);
    expect(labels['layout']['text-allow-overlap'], false);
    expect(map.style.layers['nowave-depth-soundings']!['minzoom'], 13);
    for (final layer in map.style.layers.values.where(
      (l) => l['id'].toString().startsWith('nowave-hazard'),
    )) {
      expect(layer['minzoom'], 10);
      final paint = layer['paint'] as Map;
      switch (layer['type']) {
        case 'fill':
          expectMarksFade(paint['fill-opacity'], nominal: .07);
        case 'line':
          expectMarksFade(paint['line-opacity'], nominal: .8);
        case 'symbol':
          expectMarksFade(paint['icon-opacity']);
      }
    }
    for (final source in map.style.sources.values) {
      expect(source['type'], 'geojson');
      expect(source['tolerance'], 0);
      expect(source['maxzoom'], 18);
      expect(source['attribution'], contains('DTM 2024'));
    }
    // No label queries or state writes exist: a missing/failed annotation
    // cannot disable a previously visible line.
    expect(map.states, isEmpty);
  });
  test('familles de dangers et fallback inconnu sont distincts', () {
    final layer = HydrographyLayer.layers().last as SymbolLayer;
    final icons = [
      for (final type in ['rock', 'wreck', 'obstruction', 'unqualified'])
        evaluate(layer.iconImageExpression!, {'hazard_type': type}),
    ];
    expect(icons.toSet().length, 4);
    expect(icons.last, 'nowave-hazard-unknown');
  });
  test('rochers : état publié et inconnu restent distincts', () {
    final layer = HydrographyLayer.layers().last as SymbolLayer;
    for (final state in [
      'unknown',
      'always_dry',
      'covers_and_uncovers',
      'awash',
      'always_submerged',
    ]) {
      final icon = evaluate(layer.iconImageExpression!, {
        'hazard_type': 'rock',
        'water_level': state,
      });
      expect(
        icon,
        {
          'unknown': 'nowave-hazard-rock-unknown',
          'always_dry': 'nowave-hazard-rock-exposed',
          'covers_and_uncovers': 'nowave-hazard-rock-drying',
          'awash': 'nowave-hazard-rock-awash',
          'always_submerged': 'nowave-hazard-rock-submerged',
        }[state],
      );
    }
  });
  test(
    'installation concurrente unique, reload complet et erreur retentable',
    () async {
      final map = HydroMap();
      final layer = HydrographyLayer(
        apiBaseUrl: 'https://api.example.com/gateway/',
      );
      await Future.wait([layer.addTo(map), layer.addTo(map)]);
      expect(map.style.sources.length, 3);
      expect(map.style.layers.length, 7);
      expect(map.style.images.length, 8);
      map.style.sources.clear();
      map.style.layers.clear();
      map.style.images.clear();
      map.style.reject = true;
      await expectLater(layer.addTo(map), throwsA(isA<PlatformException>()));
      map.style.reject = false;
      await layer.addTo(map);
      expect(map.style.layers.length, 7);
      expect(
        map.style.layers.keys.toList().indexOf('nowave-depth-soundings'),
        lessThan(
          map.style.layers.keys.toList().indexOf('nowave-hazard-points'),
        ),
      );
    },
  );
}
