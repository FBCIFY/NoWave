import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Lowest-priority globe camera, resumed when the user releases the map.
/// A frame clock avoids repeated native easing ramps; only longitude is written, leaving zoom, padding, pitch and bearing
/// untouched. There is at most one platform call in flight and no frame queue.
class GlobeRotationController {
  GlobeRotationController({
    required Future<void> Function(CameraOptions) moveCamera,
    Ticker Function(TickerCallback)? createTicker,
  }) {
    _moveCamera = moveCamera;
    _ticker = (createTicker ?? Ticker.new)(_tick);
  }

  static const degreesPerSecond = 2.0;
  // At 2°/s each 30 Hz step is subpixel on a phone-sized globe. Limit platform
  // traffic without changing angular speed or queuing frames on fast displays.
  static const cameraUpdateInterval = Duration(milliseconds: 33);
  static const minZoom = 0.0;
  static const maxZoom = 4.5;

  late final Future<void> Function(CameraOptions) _moveCamera;
  late final Ticker _ticker;
  CameraState? _camera;
  Future<void>? _pending;
  bool _ready = false;
  bool _visible = true;
  bool _reduceMotion = false;
  bool _dismissed = true;
  bool _disposed = false;
  double _startLongitude = 0;
  double _latitude = 0;
  Duration? _lastCameraFrame;

  bool get isRotating => !_disposed && _ticker.isActive;
  bool get dismissed => _dismissed;

  static double normalizeLongitude(double longitude) =>
      (longitude + 180) % 360 - 180;

  static bool allowsZoom(double zoom) =>
      zoom.isFinite && zoom >= minZoom && zoom <= maxZoom;

  void cameraChanged(CameraState camera) {
    if (_disposed) return;
    _camera = camera;
    _reconcile();
  }

  void configure({
    required bool ready,
    required bool visible,
    required bool reduceMotion,
  }) {
    if (_disposed) return;
    _ready = ready;
    _visible = visible;
    _reduceMotion = reduceMotion;
    _reconcile();
  }

  bool get _allowed =>
      !_disposed &&
      !_dismissed &&
      _ready &&
      _visible &&
      !_reduceMotion &&
      _camera != null &&
      allowsZoom(_camera!.zoom) &&
      _camera!.center.coordinates.lng.isFinite &&
      _camera!.center.coordinates.lat.isFinite;

  void _reconcile() {
    if (!_allowed) {
      if (isRotating) _ticker.stop();
      return;
    }
    if (isRotating || _pending != null) return;
    _startLongitude = _camera!.center.coordinates.lng.toDouble();
    _latitude = _camera!.center.coordinates.lat.toDouble();
    _lastCameraFrame = null;
    // Ticker elapsed time is monotonic and starts afresh on every resume.
    // Background time never contributes to the next longitude.
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    if (!isRotating || !_allowed || _pending != null) return;
    final lastFrame = _lastCameraFrame;
    if (lastFrame != null && elapsed - lastFrame < cameraUpdateInterval) return;
    _lastCameraFrame = elapsed;
    final longitude = normalizeLongitude(
      _startLongitude +
          degreesPerSecond *
              elapsed.inMicroseconds /
              Duration.microsecondsPerSecond,
    );
    final camera = CameraOptions(
      center: Point(coordinates: Position(longitude, _latitude)),
    );
    _pending = _send(camera);
  }

  Future<void> _send(CameraOptions camera) async {
    try {
      await Future<void>.sync(() => _moveCamera(camera));
    } catch (error) {
      // Fail closed: a broken map must not cause endless platform retries.
      _dismissed = true;
      debugPrint('Rotation du globe suspendue : $error');
    } finally {
      _pending = null;
      _reconcile();
    }
  }

  /// Starts from the latest native camera after touch and inertia have ended.
  /// GPS and business camera commands can keep this suspended through readiness.
  void resumeWhenIdle() {
    if (_disposed ||
        !_ready ||
        !_visible ||
        _reduceMotion ||
        _camera == null ||
        !allowsZoom(_camera!.zoom)) {
      return;
    }
    _dismissed = false;
    _reconcile();
  }

  /// Stops until the next idle notification after a user interaction. Synchronous stop takes priority over
  /// touch; camera commands can await the already submitted platform call.
  Future<void> stopForInteraction() {
    if (_disposed) return Future<void>.value();
    _dismissed = true;
    _reconcile();
    return _pending ?? Future<void>.value();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker.dispose();
    _camera = null;
  }
}
