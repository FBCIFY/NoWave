import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/map/location_marker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Style extends Fake implements StyleManager {
  final updates = <Map<String, dynamic>>[];
  final imageIds = <String>[];
  final imageScales = <double>[];
  final installed = <String, Map<String, dynamic>>{};
  final layers = <String>{};
  final sources = <String>{};
  final mastData = <Map<String, dynamic>>[];
  Completer<void>? gate;

  /// Couches et source déjà là, comme après une première installation.
  void installAll() {
    layers.addAll([LocationMarker.layerId, LocationMarker.mastLayerId]);
    sources.add(LocationMarker.mastSourceId);
  }

  @override
  Future<bool> styleLayerExists(String id) async => layers.contains(id);

  @override
  Future<bool> styleSourceExists(String id) async => sources.contains(id);

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
    imageIds.add(id);
    imageScales.add(scale);
    expect(image.data, isNotEmpty);
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map<String, dynamic>;
    installed[layer['id'] as String] = layer;
    layers.add(layer['id'] as String);
  }

  @override
  Future<void> addStyleSource(String id, String properties) async {
    sources.add(id);
  }

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {}

  @override
  Future<void> setStyleSourceProperty(
    String id,
    String property,
    Object value,
  ) async {
    expect(id, LocationMarker.mastSourceId);
    if (property == 'data' && value is String && value.isNotEmpty) {
      mastData.add(jsonDecode(value) as Map<String, dynamic>);
    }
  }

  @override
  Future<void> setStyleLayerProperty(
    String id,
    String property,
    Object value,
  ) async {}

  @override
  Future<void> setStyleLayerProperties(String id, String properties) async {
    updates.add(jsonDecode(properties) as Map<String, dynamic>);
    await gate?.future;
  }
}

class _Map extends Fake implements MapboxMap {
  @override
  final _Style style = _Style();
}

/// Laisse le glissement atteindre la dernière position.
Future<void> _glide() =>
    Future.delayed(LocationMarker.glideDuration + const Duration(seconds: 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('350° reste 350° sans décalage fixe, cercles ni surcouche bleue', () {
    final marker = LocationMarker.layer(
      latitude: 43.0853,
      longitude: 5.9342,
      heading: 350,
    );
    expect(marker.location, [43.0853, 5.9342, 0]);
    expect(marker.bearing, 350);
    expect(marker.bearingImageSize, 1);
    expect(marker.bearingImageExpression, [
      'step',
      ['zoom'],
      'nowave-location-arrow-small',
      9.0,
      'nowave-location-arrow-large',
    ]);
    expect(marker.accuracyRadius, 0);
    expect(marker.emphasisCircleRadius, 0);
    expect(marker.topImage, isNull);
    expect(marker.shadowImage, isNull);
  });

  test('sans cap, disque de taille inchangée', () {
    final marker = LocationMarker.layer(
      latitude: 0,
      longitude: 0,
      heading: null,
    );
    expect(marker.bearingImage, 'nowave-location-dot');
    expect(marker.bearingImageExpression, isNull);
    expect(marker.bearingImageSize, 1);
  });

  test('les mises à jour transmettent le cap et glissent vers la dernière position', () async {
    final marker = LocationMarker();
    addTearDown(marker.dispose);
    final map = _Map();
    map.style.installAll();
    final gate = map.style.gate = Completer<void>();
    final first = marker.update(
      map,
      pixelRatio: 2,
      latitude: 43,
      longitude: 5,
      heading: 350,
    );
    await pumpEventQueue();
    marker.update(map, pixelRatio: 2, latitude: 44, longitude: 6, heading: 359);
    final last = marker.update(
      map,
      pixelRatio: 2,
      latitude: 45,
      longitude: 7,
      heading: 1,
    );
    gate.complete();
    await Future.wait([first, last]);
    expect(map.style.updates.first['bearing'], 350);
    expect(map.style.updates.first['location'], [43, 5, 0]);
    expect(map.style.updates.last['bearing'], 1);
    // Pas de saut : la position est encore en chemin.
    expect(map.style.updates.last['location'][0], lessThan(45));

    await _glide();
    expect(map.style.updates.last['location'], [
      closeTo(45, 1e-9),
      closeTo(7, 1e-9),
      0,
    ]);
    expect(map.style.updates.last.containsKey('bearing-image-size'), false);
    // Le mât suit la même position, en [longitude, latitude].
    expect(map.style.mastData.last['geometry']['coordinates'], [
      closeTo(7, 1e-9),
      closeTo(45, 1e-9),
    ]);

    final sent = map.style.mastData.length;
    await marker.update(
      map,
      pixelRatio: 2,
      latitude: 45,
      longitude: 7,
      heading: null,
    );
    expect(map.style.updates.last['bearing-image'], 'nowave-location-dot');
    // Position inchangée : la source du mât n'est pas réécrite.
    expect(map.style.mastData, hasLength(sent));
  });

  test(
    'installation et reload conservent la taille physique des PNG',
    () async {
      final marker = LocationMarker();
      addTearDown(marker.dispose);
      final map = _Map();
      await marker.update(
        map,
        pixelRatio: 2,
        latitude: 43,
        longitude: 5,
        heading: 350,
      );
      expect(map.style.imageScales, [2, 2, 2, 2]);
      final indicator = map.style.installed[LocationMarker.layerId]!;
      final paint = indicator['paint'] as Map<String, dynamic>;
      expect(paint['bearing'], 350);
      expect(paint['bearing-image-size'], 1);
      expect(paint['accuracy-radius'], 0);
      expect(paint.containsKey('top-image'), false);

      // Le mât, debout face à l'écran, dans l'emplacement du chevron : sous
      // les pastilles des signalements.
      final mast = map.style.installed[LocationMarker.mastLayerId]!;
      expect(mast['source'], LocationMarker.mastSourceId);
      expect(mast['slot'], 'top');
      expect(mast['layout']['icon-anchor'], 'bottom');
      expect(mast['layout']['icon-pitch-alignment'], 'viewport');
      expect(mast['layout']['icon-rotation-alignment'], 'viewport');
      expect(map.style.mastData.last['geometry']['coordinates'], [5, 43]);

      map.style
        ..layers.clear()
        ..sources.clear();
      await marker.update(
        map,
        pixelRatio: 2,
        latitude: 43,
        longitude: 5,
        heading: 1,
      );
      expect(map.style.imageScales, [2, 2, 2, 2, 2, 2, 2, 2]);
      expect(
        map.style.installed[LocationMarker.layerId]!['paint']['bearing'],
        1,
      );
      expect(map.style.layers, contains(LocationMarker.mastLayerId));
    },
  );

  test('un nouveau pavillon réenregistre l’image du mât', () async {
    final marker = LocationMarker();
    addTearDown(marker.dispose);
    final map = _Map();
    map.style.installAll();
    await marker.update(
      map,
      pixelRatio: 2,
      latitude: 43,
      longitude: 5,
      heading: 0,
    );
    expect(map.style.imageIds, isEmpty);

    marker.flagCountry = 'FR';
    await marker.update(
      map,
      pixelRatio: 2,
      latitude: 43,
      longitude: 5,
      heading: 0,
    );
    expect(map.style.imageIds, ['nowave-location-mast']);

    // Même pavillon : rien à redessiner.
    marker.flagCountry = 'FR';
    await marker.update(
      map,
      pixelRatio: 2,
      latitude: 43,
      longitude: 5,
      heading: 0,
    );
    expect(map.style.imageIds, hasLength(1));
  });
}
