import 'dart:convert';

import 'package:blueway/core/map/marine/marine_map_controller.dart';
import 'package:blueway/features/map/data/hydrography_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MarineMap extends Fake implements MapboxMap {
  @override
  final MarineStyle style = MarineStyle();
}

class MarineStyle extends Fake implements StyleManager {
  final sources = <String, Map>{};
  final layers = <String, Map>{};
  final images = <String>{};
  bool reject = false;
  @override
  Future<void> setProjection(StyleProjection projection) async {}
  @override
  Future<void> setStyleImportConfigProperty(
    String id,
    String config,
    Object value,
  ) async {
    expect(id, 'basemap');
    expect(config, 'colorWater');
    expect(value, '#E6F7FD');
  }

  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {
    sources[id]!.addAll(jsonDecode(properties) as Map);
  }

  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (reject) throw PlatformException(code: 'source-failure');
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
  Future<bool> hasStyleImage(String id) async => images.contains(id);
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
    images.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const local = 'http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png';

  test(
    'raster local unique, opaque aux zooms utiles, overzoom et reload',
    () async {
      final map = MarineMap();
      final marine = MarineMapController(bathymetryTilesUrl: local);
      await marine.install(map);
      await marine.install(map);
      expect(map.style.sources.length, 1);
      expect(map.style.layers.length, 1);
      final source = map.style.sources.values.single;
      final layer = map.style.layers.values.single;
      expect(source['tiles'], ['$local?v=coast-1']);
      expect(source['maxzoom'], 14);
      expect(source['volatile'], true);
      expect(source['prefetch-zoom-delta'], 0);
      expect(layer['slot'], 'bottom');
      expect(layer['minzoom'], 4); // No marine tile requests in globe view.
      expect(layer['maxzoom'], isNull); // Z14 tiles remain eligible at Z17+.
      expect(layer['paint']['raster-opacity'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        4,
        0.0,
        7,
        1.0,
      ]);
      expect(layer['paint']['raster-resampling'], 'linear');
      map.style.sources.clear();
      map.style.layers.clear();
      await marine.install(map);
      expect(map.style.sources.values.single['tiles'], ['$local?v=coast-1']);
      expect(map.style.layers.length, 1);
    },
  );

  test('absence de source sans configuration bathymétrique', () async {
    final map = MarineMap();
    await MarineMapController(bathymetryTilesUrl: '').install(map);
    expect(map.style.sources, isEmpty);
    expect(map.style.layers, isEmpty);
  });

  test('version du masque sans perdre les paramètres existants', () async {
    final map = MarineMap();
    await MarineMapController(bathymetryTilesUrl: '$local?region=europe')
        .install(map);
    expect(map.style.sources.values.single['tiles'], [
      '$local?region=europe&v=coast-1',
    ]);
  });

  test('installation réessayable après une erreur du style', () async {
    final map = MarineMap()..style.reject = true;
    final marine = MarineMapController(bathymetryTilesUrl: local);
    await expectLater(marine.install(map), throwsA(isA<PlatformException>()));
    map.style.reject = false;
    await marine.install(map);
    expect(map.style.layers.length, 1);
  });

  test('raster en fond, isobathes et chiffres au-dessus', () async {
    final map = MarineMap();
    await MarineMapController(bathymetryTilesUrl: local).install(map);
    expect(map.style.layers.keys.toList(), [
      MarineMapController.bathymetryLayerId,
    ]);
    for (final layer in HydrographyLayer.layers().whereType<LineLayer>().where(
      (l) => l.sourceLayer == 'depth_contour',
    )) {
      expect(layer.slot, LayerSlot.MIDDLE);
    }
    expect(
      (HydrographyLayer.layers().singleWhere(
        (l) => l.id == 'nowave-depth-labels',
      )).slot,
      LayerSlot.MIDDLE,
    );
  });
}
