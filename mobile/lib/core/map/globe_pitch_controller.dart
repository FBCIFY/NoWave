import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Keeps the distant camera top-down, with a reversible zoom-based transition.
/// Only pitch constraints and pitch are written; the user's center is preserved.
class GlobePitchController {
  static const flatZoom = 4.5;
  static const detailedZoom = 6.0;

  /// Carte détaillée : de la vue de dessus (0°) aux trois quarts des 85°
  /// permis par Mapbox. La carte part de ce maximum.
  static const maxPitch = 85.0 * .75;
  static const defaultPitch = maxPitch;

  double _detailedPitch = defaultPitch;
  double? _lastZoom;
  double get detailedPitch => _detailedPitch;
  CameraState? _camera;
  bool _editing = false;
  double? _followingPitch;
  bool? _flatApplied;
  bool? _gesturesApplied;
  bool _writingPitch = false;
  bool _restoringDetailedPitch = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void>? _pending;

  static double pitchAt(double zoom, double detailedPitch) {
    final t = ((zoom - flatZoom) / (detailedZoom - flatZoom)).clamp(0.0, 1.0);
    // Smoothstep avoids a sudden change in slope at either zoom boundary.
    return detailedPitch * t * t * (3 - 2 * t);
  }

  Future<void> synchronize(
    MapboxMap map,
    CameraState camera, {
    required bool editing,
    double? followingPitch,
  }) {
    if (_disposed || !camera.zoom.isFinite || !camera.pitch.isFinite) {
      return Future<void>.value();
    }
    final following =
        !editing && followingPitch != null && followingPitch.isFinite;
    if (following) {
      _detailedPitch = followingPitch.clamp(0.0, maxPitch);
      _restoringDetailedPitch = false;
    }
    if (!editing && !following && camera.zoom >= detailedZoom) {
      if ((_lastZoom != null && _lastZoom! < detailedZoom) || _editing) {
        _restoringDetailedPitch = true;
      }
      if ((camera.pitch - _detailedPitch).abs() <= .01) {
        _restoringDetailedPitch = false;
      }
    }
    if (!editing &&
        !following &&
        !_editing &&
        !_restoringDetailedPitch &&
        !_writingPitch &&
        camera.zoom >= detailedZoom &&
        (_lastZoom ?? camera.zoom) >= detailedZoom) {
      _detailedPitch = camera.pitch.clamp(0.0, maxPitch);
    }
    _lastZoom = camera.zoom;
    _camera = camera;
    _editing = editing;
    _followingPitch = following ? _detailedPitch : null;
    _revision++;
    return _pending ??= Future<void>.microtask(() => _apply(map));
  }

  Future<void> _apply(MapboxMap map) async {
    try {
      var appliedRevision = -1;
      while (!_disposed && appliedRevision != _revision) {
        appliedRevision = _revision;
        final camera = _camera!;
        final flat = _editing || camera.zoom <= flatZoom;
        final gestures = !_editing && camera.zoom >= detailedZoom;
        if (_gesturesApplied != gestures) {
          try {
            await map.gestures.updateSettings(
              GesturesSettings(pitchEnabled: gestures),
            );
            _gesturesApplied = gestures;
          } catch (_) {
            // Bounds and pitch correction still apply if gestures are unavailable.
          }
        }
        if (_disposed) return;
        if (_flatApplied != flat) {
          try {
            await map.setBounds(
              CameraBoundsOptions(minPitch: 0, maxPitch: flat ? 0 : maxPitch),
            );
            _flatApplied = flat;
          } catch (_) {
            // A later camera event retries the native constraint.
          }
        }
        if (_disposed) return;
        if (appliedRevision != _revision) continue;
        // FollowPuck owns the animated pitch. Do not restore the old globe
        // pitch while a recenter or direction transition is still in flight.
        if (_followingPitch != null && !_editing) continue;
        final pitch = _editing ? 0.0 : pitchAt(camera.zoom, _detailedPitch);
        if ((camera.pitch - pitch).abs() > .01) {
          _writingPitch = true;
          try {
            await map.setCamera(CameraOptions(pitch: pitch));
          } catch (_) {
            // Optional presentation must not interrupt GPS or report cameras.
          } finally {
            _writingPitch = false;
          }
        }
      }
    } finally {
      _pending = null;
    }
  }

  void dispose() {
    _disposed = true;
    _camera = null;
  }
}
