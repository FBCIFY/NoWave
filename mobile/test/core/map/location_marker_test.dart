import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/map/location_marker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Style extends Fake implements StyleManager {
  final updates = <Map<String, dynamic>>[];
  final imageScales = <double>[];
  Map<String, dynamic>? installed;
  bool exists = true;
  Completer<void>? gate;

  @override
  Future<bool> styleLayerExists(String id) async => exists;

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
    imageScales.add(scale);
    expect(image.data, isNotEmpty);
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    installed = jsonDecode(properties) as Map<String, dynamic>;
    exists = true;
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
    expect(marker.bearingImageSize, 1.125);
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

  test('sans cap, point orange neutre de taille inchangée', () {
    final marker = LocationMarker.layer(
      latitude: 0,
      longitude: 0,
      heading: null,
    );
    expect(marker.bearingImage, 'nowave-location-dot');
    expect(marker.bearingImageExpression, isNull);
    expect(marker.bearingImageSize, 1);
  });

  test(
    'les mises à jour transmettent le cap et la dernière position',
    () async {
      final marker = LocationMarker();
      final map = _Map();
      final gate = map.style.gate = Completer<void>();
      final first = marker.update(
        map,
        pixelRatio: 2,
        latitude: 43,
        longitude: 5,
        heading: 350,
      );
      await pumpEventQueue();
      marker.update(
        map,
        pixelRatio: 2,
        latitude: 44,
        longitude: 6,
        heading: 359,
      );
      final last = marker.update(
        map,
        pixelRatio: 2,
        latitude: 45,
        longitude: 7,
        heading: 1,
      );
      gate.complete();
      await Future.wait([first, last]);
      expect(map.style.updates, hasLength(2));
      expect(map.style.updates.first['bearing'], 350);
      expect(map.style.updates.last['bearing'], 1);
      expect(map.style.updates.last['location'], [45, 7, 0]);
      expect(map.style.updates.last['bearing-image-size'], 1.125);

      await marker.update(
        map,
        pixelRatio: 2,
        latitude: 45,
        longitude: 7,
        heading: null,
      );
      expect(map.style.updates.last['bearing-image'], 'nowave-location-dot');
      expect(map.style.updates.last['bearing-image-size'], 1);
    },
  );

  test(
    'installation et reload conservent la taille physique des PNG',
    () async {
      final marker = LocationMarker();
      final map = _Map();
      map.style.exists = false;
      await marker.update(
        map,
        pixelRatio: 2,
        latitude: 43,
        longitude: 5,
        heading: 350,
      );
      expect(map.style.imageScales, [2, 2, 2]);
      final paint = map.style.installed!['paint'] as Map<String, dynamic>;
      expect(paint['bearing'], 350);
      expect(paint['bearing-image-size'], 1.125);
      expect(paint['accuracy-radius'], 0);
      expect(paint.containsKey('top-image'), false);

      map.style.exists = false;
      await marker.update(
        map,
        pixelRatio: 2,
        latitude: 43,
        longitude: 5,
        heading: 1,
      );
      expect(map.style.imageScales, [2, 2, 2, 2, 2, 2]);
      expect(map.style.installed!['paint']['bearing'], 1);
    },
  );
}
