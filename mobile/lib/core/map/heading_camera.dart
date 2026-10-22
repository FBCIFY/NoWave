import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Turns the map toward the phone's heading frame by frame. The compass
/// arrives in steps (iOS waits for 2° of rotation): replacing the viewport at
/// each reading made the camera jump. At most one platform call is in flight
/// and no frame is queued: a slow platform skips frames, never lags.
class HeadingCamera {
  HeadingCamera({
    required this._rotate,
    required this._active,
    Ticker Function(TickerCallback)? createTicker,
  }) {
    _ticker = (createTicker ?? Ticker.new)(_tick);
  }

  /// Time for the camera to cover about 63 % of the remaining turn: long
  /// enough to hide the compass steps, short enough to feel attached.
  static const smoothing = Duration(milliseconds: 180);

  /// Closer than this, the camera lands on the heading and the ticker stops.
  static const _settled = .05;

  final Future<void> Function(double bearing) _rotate;
  final bool Function() _active;
  late final Ticker _ticker;
  double? _bearing;
  double _target = 0;
  Duration _last = Duration.zero;
  Future<void>? _pending;

  /// A reduced-motion jump waits for the call in flight, then sends the
  /// latest heading only.
  bool _jumpQueued = false;
  bool _disposed = false;

  bool get isTurning => _ticker.isActive;

  /// [from] only seeds a camera at rest: once turning, the bearing it sent
  /// itself is more precise than the camera events.
  void aim(double heading, {required double from, bool reduceMotion = false}) {
    if (_disposed || !heading.isFinite || !from.isFinite) return;
    _target = heading % 360;
    if (reduceMotion) {
      stop();
      _jump();
      return;
    }
    _bearing ??= from % 360;
    if (_ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  /// The next [aim] starts again from the camera, which may have moved.
  void stop() {
    if (_ticker.isActive) _ticker.stop();
    _bearing = null;
    _jumpQueued = false;
  }

  /// Exponential smoothing along the shortest way round, in [0, 360).
  static double step(double bearing, double target, Duration elapsed) {
    final turn = (target - bearing + 540) % 360 - 180;
    final kept = math.exp(-elapsed.inMicroseconds / smoothing.inMicroseconds);
    if ((turn * kept).abs() < _settled) return target % 360;
    return (bearing + turn * (1 - kept)) % 360;
  }

  void _tick(Duration elapsed) {
    if (!_active()) return stop();
    if (_pending != null) return;
    final bearing = _bearing;
    if (bearing == null) return stop();
    if (bearing == _target) {
      _ticker.stop();
      return;
    }
    final next = step(bearing, _target, elapsed - _last);
    _last = elapsed;
    _bearing = next;
    _pending = _send(next);
  }

  void _jump() {
    if (_pending != null) {
      _jumpQueued = true;
      return;
    }
    _pending = _send(_target);
  }

  Future<void> _send(double bearing) async {
    try {
      await _rotate(bearing);
    } catch (error) {
      debugPrint('Rotation de la caméra interrompue : $error');
      stop();
    } finally {
      _pending = null;
      if (_jumpQueued && !_disposed && _active()) {
        _jumpQueued = false;
        _jump();
      }
    }
  }

  void dispose() {
    stop();
    _disposed = true;
    _ticker.dispose();
  }
}
