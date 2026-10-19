import 'dart:math' as math;

import 'package:flutter/widgets.dart' as widgets;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../reports/domain/report_detail.dart';

/// Fits the native map's actual viewport, not a zoom chosen from a distance table.
class MapAlertCamera {
  static bool usable(geo.Position? position) =>
      position != null &&
      position.latitude.isFinite &&
      position.latitude.abs() <= 90 &&
      position.longitude.isFinite &&
      position.longitude.abs() <= 180 &&
      position.accuracy.isFinite &&
      position.accuracy >= 0 &&
      DateTime.now().difference(position.timestamp).abs() <=
          const Duration(minutes: 5);

  static MbxEdgeInsets padding(widgets.Size size, widgets.EdgeInsets safe) =>
      MbxEdgeInsets(
        top: math.min(safe.top + 132, size.height * .3),
        bottom: math.min(safe.bottom + 116, size.height * .28),
        left: math.min(48, size.width * .2),
        right: math.min(96, size.width * .28),
      );

  static Future<CameraOptions> fit(
    MapboxMap map,
    ReportDetail report,
    geo.Position? position,
    widgets.EdgeInsets safe,
  ) async {
    final viewport = await map.getSize();
    if (viewport.width <= 0 || viewport.height <= 0) {
      throw StateError('Map viewport is not ready');
    }
    final margins = padding(
      widgets.Size(viewport.width, viewport.height),
      safe,
    );
    final target = Point(
      coordinates: Position(report.longitude, report.latitude),
    );
    if (!usable(position)) {
      // Single-point fallback only. Two-point focus always uses the native fit.
      return CameraOptions(
        center: target,
        zoom: 16,
        pitch: 0,
        bearing: 0,
        padding: margins,
      );
    }
    final camera = await map.cameraForCoordinatesPadding(
      [
        target,
        Point(coordinates: Position(position!.longitude, position.latitude)),
      ],
      CameraOptions(
        pitch: 0,
        bearing: 0,
        padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      ),
      margins,
      20, // Upper bound for coincident/very close points, never a forced zoom.
      null,
    );
    if (camera.center == null ||
        camera.zoom == null ||
        !camera.zoom!.isFinite) {
      throw StateError('Native camera fitting failed');
    }
    return camera;
  }
}
