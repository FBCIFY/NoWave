import 'dart:convert';
import 'dart:async';

import 'buoy_layer_test.dart' show evaluate;

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
  Completer<List<QueriedRenderedFeature?>>? pendingQuery;
  @override
  Future<Size> getSize() async => Size(width: 360, height: 805);
  @override
  Future<List<QueriedRenderedFeature?>> queryRenderedFeatures(
    RenderedQueryGeometry geometry,
    RenderedQueryOptions options,
  ) async {
    expect(options.layerIds, ['nowave-depth-labels']);
    if (failQuery) throw StateError('native query failure');
    return pendingQuery?.future ?? rendered;
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
  test('seuil exact 12 et contrat distinct de la densité des sondes', () async {
    final map = HydroMap();
    await HydrographyLayer(apiBaseUrl: 'https://api.example.com/gateway/')
        .addTo(map);
    final layers = map.style.layers.values.toList();
    final contours = layers.where((l) => l['source-layer'] == 'depth_contour');
    expect(contours.length, 3);
    for (final c in contours) {
      expect(c['minzoom'], 12);
      expect(11.9 >= (c['minzoom'] as num), isFalse);
      expect(12.0 >= (c['minzoom'] as num), isTrue);
      expect(c['slot'], 'middle');
    }
    final major = contours.elementAt(1)['paint'] as Map;
    final minor = contours.first['paint'] as Map;
    expect(major['line-width'], greaterThan(minor['line-width']));
    expect(
      major['line-opacity'][4][2],
      greaterThan(minor['line-opacity'][4][2]),
    );
    expect(major['line-opacity'][4][1], [
      'boolean',
      ['feature-state', 'label_visible'],
      false,
    ]);
    final sounding = layers.singleWhere((l) => l['source-layer'] == 'sounding');
    expect(sounding['minzoom'], 12);
    expect(sounding['filter'], [
      'match',
      ['get', 'nature'],
      ['modeled_grid_cell', 'point_sounding'],
      true,
      false,
    ]);
    expect(sounding['layout']['text-allow-overlap'], isFalse);
    expect(sounding['layout']['text-ignore-placement'], isFalse);
    expect(sounding['layout']['symbol-sort-key'], ['get', 'value_m']);
    expect(sounding['layout']['icon-image'], isNull);
    final hazard = layers.last;
    expect(hazard['slot'], 'top');
    expect(hazard['layout']['icon-allow-overlap'], isFalse);
    expect(hazard['layout']['icon-ignore-placement'], isFalse);
    expect(jsonEncode(hazard['layout']['icon-image']), contains('rock-awash'));
    expect(
      layers.where((l) => l['source-layer'] == 'underwater_hazard').length,
      3,
    );
    final sources = map.style.sources.values.toList();
    expect(sources.map((s) => s['minzoom']), [12, 12, 12]);
    expect(sources.map((s) => s['maxzoom']), [14, 16, 14]);
    expect(sources.every((s) => s['prefetch-zoom-delta'] == 0), isTrue);
    expect(
      [
        sources.first,
        sources.last,
      ].every((s) => (s['tiles'] as List).single.toString().endsWith('?v=3')),
      isTrue,
    );
    expect(sources[1]['tiles'].single, endsWith('?v=depths-4'));
    expect(sources[1]['volatile'], isTrue);
    expect(sources[0].containsKey('volatile'), isFalse);
    expect(sources[2].containsKey('volatile'), isFalse);
    expect(sources[1]['attribution'], contains('profondeurs modélisées'));
    expect(sources[1]['attribution'], contains('DTM 2024'));
    expect(sources[1]['attribution'], contains('CC BY 4.0'));
  });
  test(
    'une ligne ne devient visible que si son chiffre est réellement placé',
    () async {
      final map = HydroMap()
        ..rendered = [placedLabel(12), placedLabel(12), placedLabel(50)];
      final layer = HydrographyLayer(
        apiBaseUrl: 'https://api.example.com/gateway/',
      );
      await layer.synchronizeContourLabels(map);
      expect(map.states, {'12': true, '50': true});
      map.rendered = [placedLabel(50)];
      await layer.synchronizeContourLabels(map);
      expect(map.states, {'12': false, '50': true});
      layer.invalidateContourLabels(map);
      map.rendered = [];
      await layer.synchronizeContourLabels(map);
      expect(map.states.values.every((v) => !v), isTrue);
    },
  );
  test('une panne de placement masque les lignes déjà visibles', () async {
    final map = HydroMap()..rendered = [placedLabel(12)];
    final layer = HydrographyLayer(
      apiBaseUrl: 'https://api.example.com/gateway/',
    );
    await layer.synchronizeContourLabels(map);
    expect(map.states['12'], true);
    map.failQuery = true;
    await layer.synchronizeContourLabels(map);
    expect(map.states['12'], false);
  });
  test(
    'une réponse de placement périmée ne réaffiche pas de courbes',
    () async {
      final map = HydroMap()..pendingQuery = Completer();
      final layer = HydrographyLayer(
        apiBaseUrl: 'https://api.example.com/gateway/',
      );
      final request = layer.synchronizeContourLabels(map);
      await Future<void>.delayed(Duration.zero);
      layer.invalidateContourLabels(map);
      map.pendingQuery!.complete([placedLabel(12)]);
      await request;
      expect(map.states, isEmpty);
    },
  );
  test(
    'valeurs publiées, répétition native, tailles et précision régionale',
    () async {
      final map = HydroMap();
      await HydrographyLayer(apiBaseUrl: 'https://api.example.com/gateway/')
          .addTo(map);
      final labels = map.style.layers['nowave-depth-labels']!;
      final layout = labels['layout'];
      expect(labels['minzoom'], 12);
      expect(layout['text-field'], ['get', 'depth_label']);
      expect(layout['symbol-placement'], 'line');
      expect(layout['symbol-spacing'], HydrographyLayer.contourSymbolSpacing);
      expect(layout['symbol-spacing'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        12,
        160,
        14,
        160,
        16,
        192,
        18,
        224,
      ]);
      expect(layout['text-rotation-alignment'], 'map');
      expect(layout['text-keep-upright'], true);
      expect(layout['text-allow-overlap'], false);
      expect(layout['text-size'], HydrographyLayer.depthTextSize);
      final sizes = HydrographyLayer.depthTextSize;
      expect(sizes, [
        'interpolate',
        ['linear'],
        ['zoom'],
        12,
        10.5,
        14,
        11.5,
        16,
        12.5,
        18,
        13.5,
      ]);
      for (final layer in map.style.layers.values.where(
        (l) => l['source-layer'] == 'depth_contour',
      )) {
        expect(
          jsonEncode(layer['filter']),
          contains('published_dtm_contour_2022'),
        );
        expect(jsonEncode(layer['filter']), contains('["<",["zoom"],15]'));
        expect(jsonEncode(layer['filter']), contains('depth_label'));
      }
      final sounding = map.style.layers['nowave-depth-soundings']!['layout'];
      expect(sounding['text-size'], sizes);
      expect(sounding['text-field'], ['get', 'depth_label']);
      expect(sounding['text-padding'], 2);
      expect(sounding['icon-image'], isNull);
    },
  );
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
