import 'dart:convert';

import 'package:blueway/features/map/data/marine_tiles.dart';
import 'package:blueway/features/map/data/port_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class PortTestMap extends Fake implements MapboxMap {
  @override
  final PortTestStyle style = PortTestStyle();
}

class PortTestStyle extends Fake implements StyleManager {
  final sources = <String, dynamic>{};
  final layers = <String, Map<String, dynamic>>{};
  int adds = 0;
  bool reject = false;

  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {}
  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (reject) throw PlatformException(code: 'offline');
    expect(sources.containsKey(id), isFalse);
    sources[id] = jsonDecode(properties);
    adds++;
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NoWave fournit les deux familles sans URL nationale dans Flutter', () {
    expect(
      PortLayer.tilesUrl,
      endsWith('/api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf'),
    );
    expect(
      MarineTiles.template('seamarks'),
      endsWith('/api/v1/map/seamarks/{z}/{x}/{y}.pbf'),
    );
    for (final credit in [
      'Shom',
      'NOAA',
      'Open Waters',
      'OpenStreetMap',
      'ODbL',
      'CC BY 4.0',
    ]) {
      expect(MarineTiles.attribution, contains(credit));
    }
  });

  test(
    'ports : installation concurrente, reload et styles validés conservés',
    () async {
      final map = PortTestMap();
      await Future.wait([PortLayer.addTo(map), PortLayer.addTo(map)]);
      expect(map.style.adds, 1);
      expect(map.style.layers.length, 5);
      final source = map.style.sources[PortLayer.sourceId] as Map;
      expect(source['tiles'], [PortLayer.tilesUrl]);
      expect(source['maxzoom'], 14);
      final layers = map.style.layers.values.toList();
      expect(layers.map((l) => l['source-layer']).toSet(), {
        'water_polygons',
        'pier_lines',
        'pier_polygons',
      });
      expect(
        layers.singleWhere((l) => l['id'] == 'nowave-port-docks')['slot'],
        'bottom',
      );
      expect(
        layers.singleWhere(
          (l) => l['id'] == 'nowave-port-breakwaters',
        )['minzoom'],
        11.5,
      );
      expect(
        layers.singleWhere(
          (l) => l['id'] == 'nowave-port-pier-polygons',
        )['paint']['fill-opacity'],
        .70,
      );
      expect(
        layers.singleWhere(
          (l) => l['id'] == 'nowave-port-groynes',
        )['paint']['line-opacity'],
        .55,
      );
      map.style.sources.clear();
      map.style.layers.clear();
      await PortLayer.addTo(map);
      expect(map.style.adds, 2);
      expect(map.style.layers.length, 5);
    },
  );

  test('une source refusée peut être réinstallée', () async {
    final map = PortTestMap()..style.reject = true;
    await expectLater(PortLayer.addTo(map), throwsA(isA<PlatformException>()));
    map.style.reject = false;
    await PortLayer.addTo(map);
    expect(map.style.layers.length, 5);
  });
}
