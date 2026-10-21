import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

typedef GlobeFlightCamera = ({
  double longitude,
  double latitude,
  double zoom,
  double bearing,
});

/// Mapbox's flyTo path (van Wijk and Nuij): zoom out, travel, zoom in.
/// Pitch is left out on purpose: the caller derives it from the zoom, whereas
/// Mapbox interpolates it over time and reaches the clouds already tilted.
class GlobeFlightPath {
  GlobeFlightPath({
    required this.from,
    required GlobeFlightCamera to,
    required Size viewport,
  }) : to = (
         // Same side of the antimeridian as the start: shortest way round.
         longitude:
             from.longitude + (to.longitude - from.longitude + 540) % 360 - 180,
         latitude: to.latitude,
         zoom: to.zoom,
         bearing: from.bearing + (to.bearing - from.bearing + 540) % 360 - 180,
       ) {
    final worldSize = _tileSize * math.pow(2, from.zoom);
    _start = _project(from.longitude, from.latitude) * worldSize;
    _delta = _project(this.to.longitude, this.to.latitude) * worldSize - _start;
    final u1 = _delta.distance;
    final w0 = math.max(viewport.width, viewport.height);
    final w1 = w0 / math.pow(2, this.to.zoom - from.zoom);

    if (u1 < 1e-6) {
      // Same center: a pure zoom, exponential so it feels constant.
      final k = w1 < w0 ? -1 : 1;
      _length = (w0 - w1).abs() < 1e-6 ? 0 : (math.log(w1 / w0) / _rho).abs();
      _width = (s) => math.exp(k * _rho * s);
      _travelled = (_) => 0;
      return;
    }
    double r(int i) {
      final b =
          (w1 * w1 - w0 * w0 + (i == 0 ? 1 : -1) * _rho4 * u1 * u1) /
          (2 * (i == 0 ? w0 : w1) * _rho2 * u1);
      return math.log(math.sqrt(b * b + 1) - b);
    }

    final r0 = r(0);
    _length = (r(1) - r0) / _rho;
    _width = (s) => _cosh(r0) / _cosh(r0 + _rho * s);
    _travelled = (s) =>
        w0 * ((_cosh(r0) * _tanh(r0 + _rho * s) - _sinh(r0)) / _rho2) / u1;
  }

  /// Curvature chosen by Mapbox: how far the flight zooms out.
  static const _rho = 1.42;
  static const _rho2 = _rho * _rho;
  static const _rho4 = _rho2 * _rho2;
  static const _tileSize = 512.0;
  static const _maxLatitude = 85.051129;

  final GlobeFlightCamera from;
  final GlobeFlightCamera to;
  late final Offset _start;
  late final Offset _delta;
  late final double _length;
  late final double Function(double) _width;
  late final double Function(double) _travelled;

  /// Camera at [t], from 0 (start) to 1 (arrival), easing already applied.
  GlobeFlightCamera at(double t) {
    if (t >= 1) return to;
    if (t <= 0) return from;
    final s = t * _length;
    final zoom = _length == 0
        ? from.zoom + (to.zoom - from.zoom) * t
        : from.zoom - math.log(_width(s)) / math.ln2;
    final travelled = _length == 0 ? t : _travelled(s);
    final worldSize = _tileSize * math.pow(2, from.zoom);
    final (longitude, latitude) = _unproject(
      (_start + _delta * travelled) / worldSize.toDouble(),
    );
    return (
      longitude: longitude,
      latitude: latitude,
      zoom: zoom,
      bearing: from.bearing + (to.bearing - from.bearing) * t,
    );
  }

  /// Web Mercator, world in [0, 1].
  static Offset _project(double longitude, double latitude) {
    final lat = latitude.clamp(-_maxLatitude, _maxLatitude) * math.pi / 180;
    return Offset(
      (longitude + 180) / 360,
      (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2,
    );
  }

  static (double, double) _unproject(Offset point) {
    final n = math.pi * (1 - 2 * point.dy);
    final latitude =
        math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
    final longitude = point.dx * 360 - 180;
    return ((longitude + 180) % 360 - 180, latitude);
  }

  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _tanh(double x) => _sinh(x) / _cosh(x);
}

/// How a [GlobeFlight] ended.
enum GlobeFlightEnd {
  /// The camera reached the end of the path.
  arrived,

  /// The platform refused a frame. The camera stays where it is; the caller
  /// hands it over to native follow, which still brings it to the target.
  refused,

  /// [GlobeFlight.fly]'s `interrupted` stopped it, or a new flight replaced it.
  interrupted,
}

/// Plays a [GlobeFlightPath] frame by frame. At most one platform call is in
/// flight and no frame is queued: a slow platform skips frames, never lags.
class GlobeFlight {
  GlobeFlight({Ticker Function(TickerCallback)? createTicker}) {
    _ticker = (createTicker ?? Ticker.new)(_tick);
  }

  late final Ticker _ticker;
  GlobeFlightPath? _path;
  Duration _duration = Duration.zero;
  late double Function(double zoom) _pitchAt;
  late Future<void> Function(CameraOptions) _moveCamera;
  late bool Function() _interrupted;
  Completer<GlobeFlightEnd>? _done;
  Future<void>? _pending;
  bool _disposed = false;

  bool get isFlying => _done != null;

  Future<GlobeFlightEnd> fly({
    required GlobeFlightPath path,
    required Duration duration,
    required double Function(double zoom) pitchAt,
    required Future<void> Function(CameraOptions) moveCamera,
    required bool Function() interrupted,
  }) {
    cancel();
    if (_disposed) return Future.value(GlobeFlightEnd.interrupted);
    _path = path;
    _duration = duration;
    _pitchAt = pitchAt;
    _moveCamera = moveCamera;
    _interrupted = interrupted;
    final done = _done = Completer<GlobeFlightEnd>();
    _ticker.start();
    return done.future;
  }

  void cancel() => _finish(GlobeFlightEnd.interrupted);

  void _tick(Duration elapsed) {
    final path = _path;
    if (path == null) return;
    if (_interrupted()) return _finish(GlobeFlightEnd.interrupted);
    if (_pending != null) return;
    final t = _duration == Duration.zero
        ? 1.0
        : (elapsed.inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    final camera = path.at(Curves.ease.transform(t));
    _pending = _send(
      CameraOptions(
        center: Point(coordinates: Position(camera.longitude, camera.latitude)),
        zoom: camera.zoom,
        bearing: camera.bearing,
        pitch: _pitchAt(camera.zoom),
      ),
      last: t >= 1,
    );
  }

  Future<void> _send(CameraOptions camera, {required bool last}) async {
    try {
      await _moveCamera(camera);
      if (last) _finish(GlobeFlightEnd.arrived);
    } catch (error) {
      debugPrint('Vol de la caméra refusé : $error');
      _finish(GlobeFlightEnd.refused);
    } finally {
      _pending = null;
    }
  }

  void _finish(GlobeFlightEnd end) {
    if (_ticker.isActive) _ticker.stop();
    _path = null;
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(end);
  }

  void dispose() {
    _finish(GlobeFlightEnd.interrupted);
    _disposed = true;
    _ticker.dispose();
  }
}
