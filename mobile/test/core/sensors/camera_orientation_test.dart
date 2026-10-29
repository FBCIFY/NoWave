import 'package:blueway/core/sensors/camera_orientation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retourne -90 degrés quand la caméra vise le sol', () {
    final inclination = calculateCameraInclinationDegrees(x: 0, y: 0, z: 9.81);

    expect(inclination, closeTo(-90, 0.01));
  });

  test('retourne 90 degrés quand la caméra vise le ciel', () {
    final inclination = calculateCameraInclinationDegrees(x: 0, y: 0, z: -9.81);

    expect(inclination, closeTo(90, 0.01));
  });

  test('retourne 0 degré quand la caméra vise l’horizon', () {
    final inclination = calculateCameraInclinationDegrees(x: 0, y: 9.81, z: 0);

    expect(inclination, closeTo(0, 0.01));
  });

  test('retourne -10 degrés quand la caméra vise un peu sous l’horizon', () {
    // Téléphone en portrait, haut basculé de 10° vers l'arrière.
    final inclination = calculateCameraInclinationDegrees(
      x: 0,
      y: 9.81 * 0.98481,
      z: 9.81 * 0.17365,
    );

    expect(inclination, closeTo(-10, 0.01));
  });

  test('ignore la rotation autour de l’axe de la caméra', () {
    // Même visée à -10°, téléphone penché de 30° sur le côté.
    final inclination = calculateCameraInclinationDegrees(
      x: 9.81 * 0.98481 * 0.5,
      y: 9.81 * 0.98481 * 0.86603,
      z: 9.81 * 0.17365,
    );

    expect(inclination, closeTo(-10, 0.01));
  });

  test('retourne null sans mesure', () {
    expect(calculateCameraInclinationDegrees(x: 0, y: 0, z: 0), isNull);
  });
}
