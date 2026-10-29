import 'dart:convert';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _measurements = PhotoCaptureMeasurements(
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

PositionEstimateService _service(MockClient client) => PositionEstimateService(
  apiService: ApiService(client: client, baseUrl: 'https://api.blueway.test/'),
  getIdToken: () async => 'firebase-token',
);

void main() {
  test('envoie les mesures authentifiées et lit la position estimée', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://api.blueway.test/api/v1/position-estimates'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), _measurements.toJson());
      return http.Response(
        jsonEncode({
          'estimated_position': {
            'type': 'Point',
            'coordinates': [-4.4862, 48.3903],
          },
          'estimated_distance_m': 11,
        }),
        200,
      );
    });

    final estimate = await _service(client).estimate(_measurements);

    expect(estimate, isNotNull);
    expect(estimate!.longitude, -4.4862);
    expect(estimate.latitude, 48.3903);
    expect(estimate.distanceMeters, 11.0);
  });

  test('renvoie null quand le backend ne peut pas estimer', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'estimated_position': null, 'estimated_distance_m': null}),
        200,
      ),
    );

    expect(await _service(client).estimate(_measurements), isNull);
  });

  test('refuse une réponse mal formée', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'estimated_position': {
            'type': 'Point',
            'coordinates': [-4.4862],
          },
          'estimated_distance_m': 11,
        }),
        200,
      ),
    );

    expect(
      _service(client).estimate(_measurements),
      throwsA(isA<FormatException>()),
    );
  });

  test('transmet les erreurs du backend', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'gps_precision_insufficient'},
        }),
        422,
      ),
    );

    expect(
      _service(client).estimate(_measurements),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          422,
        ),
      ),
    );
  });
}
