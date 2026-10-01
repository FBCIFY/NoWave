import 'package:blueway/core/sensors/camera_inclination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

AccelerometerEvent _event(double x, double y, double z) =>
    AccelerometerEvent(x, y, z, DateTime(2026));

void main() {
  test('émet une inclinaison à chaque mesure, sans attendre le cap', () async {
    final service = CameraInclinationService(
      accelerometer: Stream.fromIterable([
        for (var i = 0; i < 3; i++) _event(0, 9.81, 0),
      ]),
    );

    final values = await service.inclinationDegrees.toList();

    expect(values, hasLength(3));
    expect(values, everyElement(closeTo(0, 0.01)));
  });

  test('lisse un à-coup isolé de l’accéléromètre', () async {
    final service = CameraInclinationService(
      accelerometer: Stream.fromIterable([
        _event(0, 9.81, 0),
        _event(0, 0, 9.81), // secousse : la caméra semble viser le sol
      ]),
    );

    final values = await service.inclinationDegrees.toList();

    expect(values.last, lessThan(0));
    expect(values.last, greaterThan(-15));
  });

  test(
    'rejoint la nouvelle inclinaison quand le téléphone reste incliné',
    () async {
      final service = CameraInclinationService(
        accelerometer: Stream.fromIterable([
          _event(0, 9.81, 0),
          for (var i = 0; i < 50; i++)
            _event(0, 9.81 * 0.98481, 9.81 * 0.17365),
        ]),
      );

      final values = await service.inclinationDegrees.toList();

      expect(values.last, closeTo(-10, 0.1));
    },
  );
}
