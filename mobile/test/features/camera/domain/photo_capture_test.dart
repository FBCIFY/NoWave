import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:flutter_test/flutter_test.dart';

PhotoCaptureMeasurements _measurements({
  double azimuthDegrees = 245.5,
  DateTime? capturedAt,
}) => PhotoCaptureMeasurements(
  observerLongitude: -4.4861,
  observerLatitude: 48.3904,
  gpsAccuracyMeters: 8.2,
  azimuthDegrees: azimuthDegrees,
  inclinationDegrees: -12.4,
  cameraHeightMeters: 2.5,
  cameraHeightSource: 'default',
  cameraHeightUncertaintyMeters: 0.5,
  capturedAt: capturedAt ?? DateTime.utc(2026, 9, 30, 14, 5, 12),
);

void main() {
  test('produit le JSON attendu par position-estimates', () {
    expect(_measurements().toJson(), {
      'observer_position': {
        'type': 'Point',
        'coordinates': [-4.4861, 48.3904],
      },
      'gps_accuracy_m': 8.2,
      'azimuth_deg': 245.5,
      'inclination_deg': -12.4,
      'camera_height_m': 2.5,
      'camera_height_source': 'default',
      'camera_height_uncertainty_m': 0.5,
      'captured_at': '2026-09-30T14:05:12.000Z',
    });
  });

  test('envoie une heure locale convertie en UTC', () {
    final localTime = DateTime(2026, 9, 30, 16, 5, 12);
    final json = _measurements(capturedAt: localTime).toJson();

    expect(json['captured_at'], localTime.toUtc().toIso8601String());
    expect(json['captured_at'], endsWith('Z'));
  });

  test('ramène un azimut de 360° à 0°', () {
    expect(_measurements(azimuthDegrees: 360).toJson()['azimuth_deg'], 0);
  });

  test('ajoute focale et zoom seulement s’ils sont connus (NW-156)', () {
    final measurements = PhotoCaptureMeasurements(
      observerLongitude: -4.4861,
      observerLatitude: 48.3904,
      gpsAccuracyMeters: 8.2,
      azimuthDegrees: 245.5,
      inclinationDegrees: -12.4,
      cameraHeightMeters: 2.5,
      cameraHeightSource: 'default',
      cameraHeightUncertaintyMeters: 0.5,
      capturedAt: DateTime.utc(2026, 9, 30, 14, 5, 12),
      zoomRatio: 1,
    );

    expect(measurements.toJson(), isNot(contains('focal_length_mm')));
    expect(measurements.toJson()['zoom_ratio'], 1);

    final withFocal = measurements.withFocalLength(4.25);
    expect(withFocal.toJson(), {
      ...measurements.toJson(),
      'focal_length_mm': 4.25,
    });
  });
}
