import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:blueway/core/map/accuracy_halo.dart';

void main() {
  test('le halo est centré sur la position, de rayon la précision', () {
    final layer = AccuracyHalo.layer(
      latitude: 43.21,
      longitude: 5.54,
      accuracy: 65,
    );

    expect(layer.id, AccuracyHalo.layerId);
    expect(layer.slot, LayerSlot.MIDDLE);
    expect(layer.location, [43.21, 5.54, 0]);
    expect(layer.accuracyRadius, 65);
  });

  test('le halo ne dessine aucune image, seulement le disque', () {
    final layer = AccuracyHalo.layer(latitude: 0, longitude: 0, accuracy: 5);

    expect(layer.topImage, isNull);
    expect(layer.bearingImage, isNull);
    expect(layer.shadowImage, isNull);
  });
}
