import 'package:flutter/services.dart';

import 'camera_azimuth.dart';

/// Axe de visée de la caméra arrière en continu, sur Android (NW-150).
///
/// Lit le capteur de rotation fusionné (le même que `precise_compass`) via
/// le canal natif de `MainActivity`. Sur iOS, le cap de CoreLocation suffit.
class CameraAxisService {
  static const _channel = EventChannel('fr.blueway.app/rotation_matrix');

  CameraAxisService({Stream<List<double>>? rotationMatrices})
    : _rotationMatrices =
          rotationMatrices ??
          _channel.receiveBroadcastStream().map(
            (event) => (event as List).cast<double>(),
          );

  /// Même lissage que l'inclinaison : environ 0,15 s à 50 Hz.
  static const smoothingFactor = 0.12;

  final Stream<List<double>> _rotationMatrices;

  Stream<CameraAxis> get axis async* {
    CameraAxis? smoothed;

    await for (final matrix in _rotationMatrices) {
      final measured = cameraAxisFromRotationMatrix(matrix);
      // On lisse le vecteur, pas l'angle : pas de saut entre 359° et 0°.
      smoothed = smoothed == null
          ? measured
          : (
              east: _smooth(smoothed.east, measured.east),
              north: _smooth(smoothed.north, measured.north),
              up: _smooth(smoothed.up, measured.up),
            );
      yield smoothed;
    }
  }

  static double _smooth(double previous, double measured) =>
      previous + smoothingFactor * (measured - previous);
}
