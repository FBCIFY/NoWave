import 'dart:math' as math;

import 'package:flutter/widgets.dart' as widgets;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/map/globe_pitch_controller.dart';
import '../../reports/domain/report_detail.dart';

/// Fits the native map's actual viewport, not a zoom chosen from a distance table.
///
/// [viewport] vient de la mise en page Flutter : `MapboxMap.getSize()` lève
/// « Not available. » sur iOS.
class MapAlertCamera {
  /// Zoom minimal de consultation, sans reculer une carte déjà plus proche.
  static const detailZoom = 13.0;

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
    widgets.EdgeInsets safe, {
    required widgets.Size viewport,
    double bearing = 0,
    double pitch = 0,
  }) async {
    if (viewport.width <= 0 || viewport.height <= 0) {
      throw StateError('Map viewport is not ready');
    }
    final margins = padding(viewport, safe);
    final target = Point(
      coordinates: Position(report.longitude, report.latitude),
    );
    if (!usable(position)) {
      // Single-point fallback only. Two-point focus always uses the native fit.
      return CameraOptions(
        center: target,
        zoom: 16,
        pitch: pitch,
        bearing: bearing,
        padding: margins,
      );
    }
    final camera = await map.cameraForCoordinatesPadding(
      [
        target,
        Point(coordinates: Position(position!.longitude, position.latitude)),
      ],
      CameraOptions(
        pitch: pitch,
        bearing: bearing,
        padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      ),
      margins,
      17, // Keep local context when user and report are almost coincident.
      null,
    );
    if (camera.center == null ||
        camera.zoom == null ||
        !camera.zoom!.isFinite) {
      throw StateError('Native camera fitting failed');
    }
    return camera;
  }

  /// La fiche occupe [panelHeight] en bas, ou en haut avec [top] (Mes
  /// alertes) : le centre vise le milieu de la carte restée visible.
  static MbxEdgeInsets detailPadding(
    widgets.Size viewport,
    double panelHeight, {
    bool top = false,
  }) {
    final height = panelHeight.clamp(0, viewport.height).toDouble();
    return MbxEdgeInsets(
      top: top ? height : 0,
      left: 0,
      bottom: top ? 0 : height,
      right: 0,
    );
  }

  /// Fiche ouverte : le signalement au centre de la carte visible à côté
  /// de la fiche, au zoom de consultation, incliné de [pitch].
  static Future<CameraOptions> detail(
    MapboxMap map,
    ReportDetail report, {
    required CameraState from,
    double? currentZoom,
    required double bearing,
    required widgets.Size viewport,
    required double panelHeight,
    bool panelOnTop = false,
    double minZoom = 0,
    double pitch = GlobePitchController.defaultPitch,
  }) async {
    if (viewport.width <= 0 || viewport.height <= 0) {
      throw StateError('Map viewport is not ready');
    }
    final zoom = math.max(detailZoom, currentZoom ?? from.zoom);
    return CameraOptions(
      center: Point(coordinates: Position(report.longitude, report.latitude)),
      zoom: math.max(zoom, minZoom),
      pitch: pitch,
      bearing: bearing,
      padding: detailPadding(viewport, panelHeight, top: panelOnTop),
    );
  }
}
