import 'package:sensors_plus/sensors_plus.dart';

import 'camera_orientation.dart';

/// Inclinaison de la caméra arrière en continu, tirée de l'accéléromètre.
///
/// Sur iOS, `precise_compass` n'envoie le tangage et le roulis qu'avec un
/// changement de cap d'au moins 2° : incliner le téléphone sans tourner ne
/// rafraîchissait rien. L'accéléromètre émet lui à cadence fixe.
class CameraInclinationService {
  CameraInclinationService({Stream<AccelerometerEvent>? accelerometer})
    : _accelerometer =
          accelerometer ??
          accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);

  /// Part de la nouvelle mesure à chaque échantillon (filtre passe-bas) :
  /// à 50 Hz, environ 0,15 s de lissage, assez pour gommer le tremblement de
  /// la main sans retard visible.
  static const smoothingFactor = 0.12;

  final Stream<AccelerometerEvent> _accelerometer;

  Stream<double> get inclinationDegrees async* {
    double? x;
    double? y;
    double? z;

    await for (final event in _accelerometer) {
      // On lisse le vecteur gravité, pas l'angle : les trois axes restent
      // cohérents entre eux.
      x = x == null ? event.x : x + smoothingFactor * (event.x - x);
      y = y == null ? event.y : y + smoothingFactor * (event.y - y);
      z = z == null ? event.z : z + smoothingFactor * (event.z - z);

      final inclination = calculateCameraInclinationDegrees(x: x, y: y, z: z);

      if (inclination != null) {
        yield inclination;
      }
    }
  }
}
