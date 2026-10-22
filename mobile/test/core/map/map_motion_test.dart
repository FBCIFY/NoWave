import 'package:blueway/core/map/map_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

CameraState state(double longitude, double latitude, double zoom) =>
    CameraState(
      center: Point(coordinates: Position(longitude, latitude)),
      zoom: zoom,
      bearing: 0,
      pitch: 0,
      padding: MbxEdgeInsets(top: 0, left: 0, right: 0, bottom: 0),
    );

void main() {
  test(
    'le passage de date proche ne devient pas un voyage autour du monde',
    () {
      final close = MapMotion.focusDurationMs(
        state(179.999, 43, 14),
        CameraOptions(
          center: Point(coordinates: Position(-179.999, 43)),
          zoom: 14,
        ),
      );
      final far = MapMotion.focusDurationMs(
        state(5, 43, 14),
        CameraOptions(center: Point(coordinates: Position(120, -30)), zoom: 4),
      );
      expect(close, inInclusiveRange(240, 280));
      expect(far, 500);
    },
  );

  test('la durée est bornée, y compris au pôle et au zoom maximal', () {
    for (final latitude in [-90.0, 0.0, 90.0]) {
      for (final zoom in [0.0, 14.0, 22.0]) {
        expect(
          MapMotion.focusDurationMs(
            state(0, latitude, zoom),
            CameraOptions(
              center: Point(coordinates: Position(180, latitude)),
              zoom: 16,
            ),
          ),
          inInclusiveRange(240, 500),
        );
      }
    }
  });

  test('les gestes simultanés restent libres sur les deux plateformes', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final settings = MapMotion.gestures(platform);
      expect(settings.scrollMode, ScrollMode.HORIZONTAL_AND_VERTICAL);
      expect(settings.simultaneousRotateAndPinchToZoomEnabled, isTrue);
      expect(settings.pinchPanEnabled, isTrue);
      expect(settings.focalPoint, isNull);
      expect(settings.rotateDecelerationEnabled, isFalse);
    }
  });
}
