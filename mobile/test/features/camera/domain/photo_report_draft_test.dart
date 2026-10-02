import 'dart:typed_data';

import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:blueway/features/camera/domain/photo_report_draft.dart';
import 'package:blueway/features/camera/domain/position_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

final _capture = PhotoCapture(
  jpegBytes: Uint8List(0),
  measurements: PhotoCaptureMeasurements(
    observerLongitude: -4.4861,
    observerLatitude: 48.3904,
    gpsAccuracyMeters: 8.2,
    azimuthDegrees: 245.5,
    inclinationDegrees: -12.4,
    cameraHeightMeters: 2.5,
    cameraHeightSource: 'default',
    cameraHeightUncertaintyMeters: 0.5,
    capturedAt: DateTime.utc(2026, 9, 30, 14, 5, 12),
  ),
);

void main() {
  test('propose le point estimé par le backend', () {
    final draft = PhotoReportDraft(
      capture: _capture,
      estimate: const PositionEstimate(
        longitude: -4.4862,
        latitude: 48.3903,
        distanceMeters: 11,
      ),
    );

    expect(draft.initialLongitude, -4.4862);
    expect(draft.initialLatitude, 48.3903);
  });

  test('part de la position du téléphone sans estimation', () {
    final draft = PhotoReportDraft(capture: _capture, estimate: null);

    expect(draft.initialLongitude, -4.4861);
    expect(draft.initialLatitude, 48.3904);
  });
}
