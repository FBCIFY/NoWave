import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Native gestures remain in charge while fingers touch the map. Android's
/// release animation and iOS's decay factor are configured by the small native
/// bridge; no per-frame gesture work crosses the Flutter channel.
class MapMotion {
  static const clusterDurationMs = 240;
  static const _channel = MethodChannel('fr.blueway.app/map_motion');

  static GesturesSettings gestures(TargetPlatform platform) => GesturesSettings(
    scrollEnabled: true,
    scrollMode: ScrollMode.HORIZONTAL_AND_VERTICAL,
    rotateEnabled: true,
    pinchToZoomEnabled: true,
    pinchPanEnabled: true,
    simultaneousRotateAndPinchToZoomEnabled: true,
    scrollDecelerationEnabled: platform != TargetPlatform.android,
    rotateDecelerationEnabled: false,
    pinchToZoomDecelerationEnabled: false,
  );

  static Future<void> configure(
    MapboxMap map, {
    required bool reduceMotion,
  }) async {
    try {
      final settings = gestures(defaultTargetPlatform);
      if (reduceMotion) settings.scrollDecelerationEnabled = false;
      // Keep native momentum if the view is not attached yet. The Android
      // bridge disables it only after its replacement listener is installed.
      if (defaultTargetPlatform == TargetPlatform.android && !reduceMotion) {
        settings.scrollDecelerationEnabled = true;
      }
      await map.gestures.updateSettings(settings);
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android) {
        final applied = await _channel.invokeMethod<bool>('configure', {
          'reduceMotion': reduceMotion,
          'iosDecay': 0.988,
          'androidDurationMs': 200,
          'androidMaxVelocityDp': 1000.0,
        });
        if (applied != true) debugPrint('Carte native pas encore attachée.');
        if (applied == true) {
          debugPrint(
            'MapMotion appliqué : $defaultTargetPlatform, inertie courte.',
          );
        }
      }
    } on MissingPluginException {
      // Widget tests do not instantiate either native platform view.
    } catch (error) {
      debugPrint('Réglages des mouvements indisponibles : $error');
    }
  }

  /// Geographic displacement is scaled to the current viewport. Antimeridian
  /// crossings use the short arc, so a nearby report does not trigger a long
  /// animation merely because its longitude has changed sign.
  static int focusDurationMs(CameraState current, CameraOptions target) {
    final center = target.center;
    if (center == null) return 240;
    final from = current.center.coordinates;
    final to = center.coordinates;
    final longitudeDelta = ((to.lng - from.lng + 540) % 360 - 180).abs();
    final latitudeDelta = (to.lat - from.lat).abs();
    final meanLatitude = (from.lat + to.lat) / 2 * math.pi / 180;
    final degrees = math.max(
      latitudeDelta,
      longitudeDelta * math.cos(meanLatitude).abs(),
    );
    final viewportDegrees = 360 / math.pow(2, current.zoom.clamp(0, 22));
    final screens = degrees / viewportDegrees;
    final zoomDelta = ((target.zoom ?? current.zoom) - current.zoom).abs();
    final travel = math.max(screens / 4, zoomDelta / 8).clamp(0.0, 1.0);
    return (240 + 260 * travel).round();
  }
}
