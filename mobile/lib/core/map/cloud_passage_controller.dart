import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Camera-driven foreground presentation. No clock, ticker, smoothing queue or
/// style mutation: the same camera always produces the same cloud field.
class CloudPassageController extends ChangeNotifier {
  static const startZoom = 4.5;
  static const endZoom = 6.2;

  double zoom = 0;
  double longitude = 0;
  double latitude = 0;
  double bearing = 0;
  double pitch = 0;

  bool get visible => zoom > startZoom && zoom < endZoom;

  void setCamera({
    required double zoom,
    required double longitude,
    required double latitude,
    required double bearing,
    required double pitch,
  }) {
    if (!zoom.isFinite ||
        !longitude.isFinite ||
        !latitude.isFinite ||
        !bearing.isFinite ||
        !pitch.isFinite) {
      return;
    }
    if (this.zoom == zoom &&
        this.longitude == longitude &&
        this.latitude == latitude &&
        this.bearing == bearing &&
        this.pitch == pitch) {
      return;
    }
    final wasVisible = visible;
    this.zoom = zoom;
    this.longitude = longitude;
    this.latitude = latitude;
    this.bearing = bearing;
    this.pitch = pitch;
    // Paint once on exit to clear the foreground, otherwise no raster work
    // outside the passage even when the native map keeps moving.
    if (visible || wasVisible) notifyListeners();
  }
}

/// The three depth envelopes overlap. Each bank grows and moves away from the
/// vanishing point while its own plane is passed, rather than whitening a screen.
@immutable
class CloudPassagePlane {
  const CloudPassagePlane({
    required this.enter,
    required this.crest,
    required this.exit,
    required this.opacity,
    required this.speed,
  });

  final double enter;
  final double crest;
  final double exit;
  final double opacity;
  final double speed;

  static const planes = [
    CloudPassagePlane(
      enter: 4.5,
      crest: 4.98,
      exit: 5.75,
      opacity: .48,
      speed: .8,
    ),
    CloudPassagePlane(
      enter: 4.65,
      crest: 5.2,
      exit: 6.05,
      opacity: .82,
      speed: 1.15,
    ),
    CloudPassagePlane(
      enter: 4.85,
      crest: 5.43,
      exit: 6.2,
      opacity: .88,
      speed: 1.85,
    ),
  ];

  static double smooth(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  double opacityAt(double zoom) =>
      opacity *
      smooth((zoom - enter) / (crest - enter)) *
      (1 - smooth((zoom - crest) / (exit - crest)));

  double scaleAt(double zoom) => math.exp((zoom - enter) * speed) * .72;
}
