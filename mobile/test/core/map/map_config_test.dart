import 'package:flutter_test/flutter_test.dart';
import 'package:blueway/core/map/map_config.dart';

void main() {
  test('suivi natif actif, sans point bleu ni image ni cercle Mapbox', () {
    final settings = MapConfig.locationPuckSettings();
    final puck = settings.locationPuck?.locationPuck2D;

    expect(settings.enabled, true);
    expect(settings.puckBearingEnabled, false);
    expect(settings.pulsingEnabled, false);
    expect(settings.showAccuracyRing, false);
    expect(settings.locationPuck?.locationPuck3D, isNull);
    // Vide retire l'image native ; null la conserverait sur Android.
    expect(puck?.topImage, isEmpty);
    expect(puck?.bearingImage, isEmpty);
    expect(puck?.shadowImage, isEmpty);
    expect(puck?.opacity, 0);
  });
}
