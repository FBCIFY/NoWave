import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:blueway/core/map/map_config.dart';

void main() {
  test('de près, le curseur est la flèche 3D', () {
    final puck = MapConfig.locationPuckSettings().locationPuck;

    expect(puck?.locationPuck3D, isNotNull);
    expect(puck?.locationPuck2D, isNull);
  });

  test('de loin, le curseur est le point bleu de Mapbox', () {
    final puck = MapConfig.locationPuckSettings(zoomedOut: true).locationPuck;

    expect(puck?.locationPuck2D, isA<DefaultLocationPuck2D>());
    expect(puck?.locationPuck3D, isNull);
  });
}
