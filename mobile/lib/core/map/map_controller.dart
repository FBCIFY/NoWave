import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Seul accès au moteur natif ; les parcours métier peuvent utiliser un fake.
abstract interface class NoWaveMapController {
  CameraPosition get camera;
  Future<void> move(CameraPosition position, {Duration? duration});
  Future<void> setPadding(EdgeInsets padding);
  Future<LatLng> coordinateForPixel(Offset pixel);
  Future<Offset> pixelForCoordinate(LatLng coordinate);
}

/// Les projections Android du plugin retournent des pixels physiques ; iOS et
/// web utilisent les points logiques Flutter. La conversion reste dans l'adaptateur.
class MapProjectionUnits {
  const MapProjectionUnits({required this.platform, required this.pixelRatio});
  final TargetPlatform platform;
  final double pixelRatio;
  double get scale =>
      !kIsWeb && platform == TargetPlatform.android ? pixelRatio : 1;
  math.Point<double> toNative(Offset point) =>
      math.Point(point.dx * scale, point.dy * scale);
  Offset toFlutter(math.Point point) =>
      Offset(point.x / scale, point.y / scale);
}

class MapLibreControllerAdapter implements NoWaveMapController {
  MapLibreControllerAdapter(this.controller, this.units);
  final MapLibreMapController controller;
  final MapProjectionUnits units;
  @override
  CameraPosition get camera => controller.cameraPosition!;
  @override
  Future<void> move(CameraPosition position, {Duration? duration}) async {
    final update = CameraUpdate.newCameraPosition(position);
    if (duration == null) {
      await controller.moveCamera(update);
    } else {
      await controller.animateCamera(update, duration: duration);
    }
  }

  @override
  Future<void> setPadding(EdgeInsets padding) =>
      controller.updateContentInsets(padding);
  @override
  Future<LatLng> coordinateForPixel(Offset pixel) =>
      controller.toLatLng(units.toNative(pixel));
  @override
  Future<Offset> pixelForCoordinate(LatLng coordinate) async =>
      units.toFlutter(await controller.toScreenLocation(coordinate));
}

EdgeInsets paddingForMarker(Offset tip, Size mapSize) {
  final delta = tip - mapSize.center(Offset.zero);
  return EdgeInsets.fromLTRB(
    math.max(0, delta.dx * 2),
    math.max(0, delta.dy * 2),
    math.max(0, -delta.dx * 2),
    math.max(0, -delta.dy * 2),
  );
}
