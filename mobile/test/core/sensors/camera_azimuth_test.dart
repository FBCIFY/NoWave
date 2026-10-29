import 'dart:math' as math;

import 'package:blueway/core/sensors/camera_azimuth.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Matrix = List<List<double>>;

double _rad(double degrees) => degrees * math.pi / 180;

_Matrix _multiply(_Matrix a, _Matrix b) => [
  for (var i = 0; i < 3; i++)
    [
      for (var j = 0; j < 3; j++)
        a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j],
    ],
];

/// Matrice Android (téléphone → terrestre, 9 valeurs ligne par ligne) d'un
/// téléphone tenu debout en portrait, la caméra arrière visant [azimuth]
/// (depuis le nord, vers l'est), relevée de [pitch] au-dessus de l'horizon et
/// tournée de [roll] autour de son axe de visée.
List<double> _rotationMatrix({
  required double azimuth,
  double pitch = 0,
  double roll = 0,
}) {
  final h = _rad(azimuth);
  final p = _rad(pitch);
  final r = _rad(roll);
  // Debout face au nord : x vers l'est, y vers le haut, z vers le sud (vers
  // l'utilisateur), donc la caméra (-z) vise le nord.
  const upright = [
    [1.0, 0.0, 0.0],
    [0.0, 0.0, -1.0],
    [0.0, 1.0, 0.0],
  ];
  // Rotation autour de z, l'axe de visée, dans le repère du téléphone.
  final rollAroundAxis = [
    [math.cos(r), -math.sin(r), 0.0],
    [math.sin(r), math.cos(r), 0.0],
    [0.0, 0.0, 1.0],
  ];
  // Relève la visée autour de l'axe est.
  final pitchUp = [
    [1.0, 0.0, 0.0],
    [0.0, math.cos(p), -math.sin(p)],
    [0.0, math.sin(p), math.cos(p)],
  ];
  // Tourne autour de la verticale, du nord vers l'est.
  final turn = [
    [math.cos(h), math.sin(h), 0.0],
    [-math.sin(h), math.cos(h), 0.0],
    [0.0, 0.0, 1.0],
  ];
  final matrix = _multiply(
    turn,
    _multiply(pitchUp, _multiply(upright, rollAroundAxis)),
  );
  return [for (final row in matrix) ...row];
}

double? _azimuthOf(List<double> matrix) =>
    cameraAzimuthDegrees(cameraAxisFromRotationMatrix(matrix));

void main() {
  test('téléphone debout : l’azimut est celui de la caméra', () {
    for (final azimuth in [0.0, 45.0, 90.0, 180.0, 245.0, 359.0]) {
      expect(
        _azimuthOf(_rotationMatrix(azimuth: azimuth)),
        closeTo(azimuth, 1e-9),
        reason: 'azimut $azimuth°',
      );
    }
  });

  test('l’inclinaison vers le haut ou le bas ne change pas l’azimut', () {
    for (final pitch in [-60.0, -10.0, 10.0, 60.0]) {
      final axis = cameraAxisFromRotationMatrix(
        _rotationMatrix(azimuth: 120, pitch: pitch),
      );
      expect(cameraAzimuthDegrees(axis), closeTo(120, 1e-9));
      expect(axis.up, closeTo(math.sin(_rad(pitch)), 1e-9));
    }
  });

  test('une rotation autour de l’axe de visée conserve la direction', () {
    for (final roll in [-90.0, -30.0, 15.0, 90.0, 180.0]) {
      expect(
        _azimuthOf(_rotationMatrix(azimuth: 300, pitch: -15, roll: roll)),
        closeTo(300, 1e-9),
        reason: 'roulis $roll°',
      );
    }
  });

  test('le cap de l’axe y (getOrientation) diffère de la visée en paysage', () {
    // Téléphone en paysage (roulis 90°) visant l'est : le haut du téléphone
    // pointe vers le nord, la caméra vers l'est.
    final matrix = _rotationMatrix(azimuth: 90, roll: 90);
    final yAxisHeading =
        (math.atan2(matrix[1], matrix[4]) * 180 / math.pi + 360) % 360;

    expect(_azimuthOf(matrix), closeTo(90, 1e-9));
    expect((yAxisHeading - 90).abs(), greaterThan(45));
  });

  test('à plat, la caméra vers le sol : pas d’azimut', () {
    // Téléphone posé écran vers le ciel : matrice identité.
    expect(_azimuthOf([1, 0, 0, 0, 1, 0, 0, 0, 1]), isNull);
    expect(_azimuthOf(_rotationMatrix(azimuth: 0, pitch: -88)), isNull);
    expect(_azimuthOf(_rotationMatrix(azimuth: 0, pitch: -80)), isNotNull);
  });

  test('ajoute la déclinaison pour obtenir l’azimut vrai', () {
    final axis = cameraAxisFromRotationMatrix(_rotationMatrix(azimuth: 358));

    expect(
      cameraTrueAzimuthDegrees(
        axis: axis,
        headingMagnetic: 10,
        headingTrue: 13,
      ),
      closeTo(1, 1e-9),
    );
    // Cap de l'axe y de part et d'autre du nord : la déclinaison reste -3°.
    expect(
      cameraTrueAzimuthDegrees(
        axis: axis,
        headingMagnetic: 1,
        headingTrue: 358,
      ),
      closeTo(355, 1e-9),
    );
  });

  test('sans cap vrai, pas d’azimut vrai', () {
    final axis = cameraAxisFromRotationMatrix(_rotationMatrix(azimuth: 90));

    expect(
      cameraTrueAzimuthDegrees(
        axis: axis,
        headingMagnetic: 90,
        headingTrue: null,
      ),
      isNull,
    );
  });

  test('refuse une matrice incomplète', () {
    expect(() => cameraAxisFromRotationMatrix([1, 0, 0]), throwsArgumentError);
  });
}
