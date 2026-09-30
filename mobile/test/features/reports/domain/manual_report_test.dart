import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:flutter_test/flutter_test.dart';

PhotoCaptureMeasurements _measurements() => PhotoCaptureMeasurements(
  observerLongitude: -4.4861,
  observerLatitude: 48.3904,
  gpsAccuracyMeters: 8.2,
  azimuthDegrees: 245.5,
  inclinationDegrees: -12.4,
  cameraHeightMeters: 2.5,
  cameraHeightSource: 'default',
  cameraHeightUncertaintyMeters: 0.5,
  capturedAt: DateTime.utc(2026, 9, 30, 14, 5, 12),
);

ManualReportRequest _request({PhotoCaptureMeasurements? positioning}) =>
    ManualReportRequest(
      clientReportId: '550e8400-e29b-41d4-a716-446655440000',
      category: ReportCategory.obstruction,
      longitude: -4.4862,
      latitude: 48.3903,
      observedAt: DateTime.utc(2026, 9, 30, 14, 5, 12),
      positioning: positioning,
    );

void main() {
  test('reste en mode manuel sans mesures photo', () {
    final json = _request().toJson();

    expect(json.containsKey('positioning_mode'), isFalse);
    expect(json.containsKey('positioning'), isFalse);
  });

  test('envoie le mode photo et les mesures de la prise de vue', () {
    final measurements = _measurements();
    final json = _request(positioning: measurements).toJson();

    expect(json['positioning_mode'], 'photo');
    expect(json['positioning'], measurements.toJson());
    expect(json['final_position'], {
      'type': 'Point',
      'coordinates': [-4.4862, 48.3903],
    });
  });

  test('une autre photo ne réutilise pas le même signalement', () {
    final measurements = _measurements();
    final request = _request(positioning: measurements);

    bool matches(PhotoCaptureMeasurements? positioning) =>
        request.matchesContent(
          category: ReportCategory.obstruction,
          longitude: -4.4862,
          latitude: 48.3903,
          description: null,
          positioning: positioning,
        );

    expect(matches(measurements), isTrue);
    expect(matches(_measurements()), isFalse);
    expect(matches(null), isFalse);
  });
}
