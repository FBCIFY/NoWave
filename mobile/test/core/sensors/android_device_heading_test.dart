import 'dart:math' as math;

import 'package:blueway/core/sensors/android_device_heading.dart';
import 'package:blueway/core/sensors/camera_azimuth.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> _multiply(List<double> a, List<double> b) => [
  for (var row = 0; row < 3; row++)
    for (var col = 0; col < 3; col++)
      a[row * 3] * b[col] +
          a[row * 3 + 1] * b[3 + col] +
          a[row * 3 + 2] * b[6 + col],
];

List<double> _z(double degrees) {
  final a = degrees * math.pi / 180;
  return [math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a), 0, 0, 0, 1];
}

List<double> _phone(double heading, double tilt, double roll) {
  final a = tilt * math.pi / 180;
  return _multiply(
    _z(-heading),
    _multiply([
      1,
      0,
      0,
      0,
      math.cos(a),
      -math.sin(a),
      0,
      math.sin(a),
      math.cos(a),
    ], _z(roll)),
  );
}

double _distance(double a, double b) => ((a - b + 540) % 360 - 180).abs();

// Référence indépendante : opérations remapCoordinateSystem d'AOSP puis
// sélection d'axes de LocationCompassEngine Mapbox Android 11.30.1.
List<double> _remap(List<double> matrix, int axisX, int axisY) {
  var axisZ = axisX ^ axisY;
  final x = (axisX & 3) - 1;
  final y = (axisY & 3) - 1;
  final z = (axisZ & 3) - 1;
  if (((x ^ ((z + 1) % 3)) | (y ^ ((z + 2) % 3))) != 0) axisZ ^= 128;
  final out = List<double>.filled(9, 0);
  for (var row = 0; row < 3; row++) {
    out[row * 3 + x] = (axisX >= 128 ? -1 : 1) * matrix[row * 3];
    out[row * 3 + y] = (axisY >= 128 ? -1 : 1) * matrix[row * 3 + 1];
    out[row * 3 + z] = (axisZ >= 128 ? -1 : 1) * matrix[row * 3 + 2];
  }
  return out;
}

double _mapboxHeading(List<double> matrix, int rotation) {
  var (x, y) = [(1, 2), (2, 129), (129, 130), (130, 1)][rotation];
  final screen = _remap(matrix, x, y);
  final pitch = math.asin(-screen[7]);
  final roll = math.atan2(-screen[6], screen[8]);
  if (pitch < -math.pi / 4) {
    (x, y) = [(1, 3), (3, 129), (129, 131), (131, 1)][rotation];
  } else if (pitch > math.pi / 4) {
    (x, y) = [(1, 131), (131, 129), (129, 3), (3, 1)][rotation];
  } else if (roll.abs() > math.pi / 2) {
    (x, y) = [(1, 130), (130, 129), (129, 2), (2, 1)][rotation];
  }
  final adjusted = _remap(matrix, x, y);
  return (math.atan2(adjusted[1], adjusted[4]) * 180 / math.pi) % 360;
}

void main() {
  test('quatre points cardinaux à plat et quatre rotations écran', () {
    for (final heading in [0.0, 90.0, 180.0, 270.0, 359.0]) {
      for (var rotation = 0; rotation < 4; rotation++) {
        final result = androidDeviceHeading(
          _phone(heading, 0, 0),
          displayRotation: rotation,
        )!;
        expect(
          _distance(result, (heading + 90 * rotation) % 360),
          lessThan(1e-9),
        );
      }
    }
  });

  test('debout : le roulis ne devient pas une erreur de cap', () {
    for (final heading in [0.0, 90.0, 180.0, 270.0, 359.0]) {
      for (final tilt in [60.0, 80.0, 89.0, 90.0, 91.0]) {
        for (final roll in [-20.0, 0.0, 20.0]) {
          for (var rotation = 0; rotation < 4; rotation++) {
            final matrix = _multiply(
              _phone(heading, tilt, roll),
              _z(90.0 * rotation),
            );
            final result = androidDeviceHeading(
              matrix,
              displayRotation: rotation,
            )!;
            expect(
              _distance(result, heading),
              lessThan(1e-9),
              reason:
                  'cap=$heading inclinaison=$tilt roulis=$roll écran=$rotation',
            );
          }
        }
      }
    }
  });

  test('matrice relevée sur appareil : ancien cap 202°, nouveau ~183°', () {
    const matrix = [
      -0.997,
      -0.055,
      0.048,
      0.055,
      -0.137,
      0.989,
      -0.048,
      0.989,
      0.139,
    ];
    final old = (math.atan2(matrix[1], matrix[4]) * 180 / math.pi) % 360;
    expect(old, closeTo(201.9, 0.1));
    expect(androidDeviceHeading(matrix), closeTo(182.8, 0.1));
  });

  test(
    'près de la verticale, 3° de roulis peuvent fausser +Y de plus de 60°',
    () {
      final matrix = _phone(180, 89, 3);
      final old = (math.atan2(matrix[1], matrix[4]) * 180 / math.pi) % 360;
      expect(_distance(old, 180), greaterThan(60));
      expect(androidDeviceHeading(matrix), closeTo(180, 1e-9));
      expect(
        cameraAzimuthDegrees(cameraAxisFromRotationMatrix(matrix)),
        closeTo(180, 1e-9),
      );
    },
  );

  test('mêmes conventions de posture que Mapbox, y compris écran inversé', () {
    for (final heading in [0.0, 90.0, 180.0, 270.0, 359.0]) {
      for (final tilt in [
        -120.0,
        -80.0,
        -30.0,
        0.0,
        30.0,
        80.0,
        120.0,
        180.0,
      ]) {
        for (final roll in [-160.0, -20.0, 0.0, 20.0, 160.0]) {
          for (var rotation = 0; rotation < 4; rotation++) {
            final matrix = _phone(heading, tilt, roll);
            expect(
              _distance(
                androidDeviceHeading(matrix, displayRotation: rotation)!,
                _mapboxHeading(matrix, rotation),
              ),
              lessThan(1e-9),
            );
          }
        }
      }
    }
  });

  test('NW-150 conserve -Z même quand la boussole choisit le haut écran', () {
    final matrix = _phone(90, 20, 30);
    final camera = cameraAzimuthDegrees(cameraAxisFromRotationMatrix(matrix))!;
    final heading = androidDeviceHeading(matrix)!;
    expect(camera, closeTo(90, 1e-9));
    expect(_distance(camera, heading), greaterThan(20));
  });

  test('refuse matrices invalides et rotation écran inconnue', () {
    expect(() => androidDeviceHeading([1, 0]), throwsArgumentError);
    expect(
      () => androidDeviceHeading(_phone(0, 0, 0), displayRotation: 4),
      throwsArgumentError,
    );
    expect(androidDeviceHeading(List.filled(9, 0)), isNull);
    expect(androidDeviceHeading(List.filled(9, double.nan)), isNull);
  });
}
