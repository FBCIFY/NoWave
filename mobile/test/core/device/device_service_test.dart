import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/device/device_position.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/device/installation_id_store.dart';

void main() {
  const installationId = '6f1c2d3e-4b5a-4c6d-8e7f-901234567890';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  DeviceService createService(MockClient client, {String platform = 'ios'}) {
    addTearDown(client.close);

    return DeviceService(
      apiService: ApiService(
        client: client,
        baseUrl: 'https://api.blueway.test/',
      ),
      getIdToken: () async => 'firebase-token',
      installationIds: InstallationIdStore(newId: () => installationId),
      platform: platform,
    );
  }

  test(
    'register envoie l’installation, la plateforme et le token FCM',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url,
          Uri.parse('https://api.blueway.test/api/v1/devices/current'),
        );
        expect(request.headers['authorization'], 'Bearer firebase-token');
        expect(request.headers['content-type'], startsWith('application/json'));
        expect(request.headers.containsKey('x-installation-id'), isFalse);
        expect(jsonDecode(request.body), {
          'installation_id': installationId,
          'platform': 'android',
          'fcm_token': 'fcm-token',
        });

        return http.Response('{"id":"device-1"}', 200);
      });

      await createService(
        client,
        platform: 'android',
      ).register(fcmToken: 'fcm-token');
    },
  );

  test('register sans token FCM envoie null pour effacer l’ancien', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.containsKey('fcm_token'), isTrue);
      expect(body['fcm_token'], isNull);

      return http.Response('{"id":"device-1"}', 200);
    });

    await createService(client).register();
  });

  test('register laisse remonter un conflit 409', () async {
    final client = MockClient((request) async {
      return http.Response('{"detail":{"code":"device_conflict"}}', 409);
    });

    await expectLater(
      createService(client).register(fcmToken: 'fcm-token'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('sendPosition envoie la mesure avec l’en-tête d’installation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(
        request.url,
        Uri.parse('https://api.blueway.test/api/v1/devices/current/position'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['x-installation-id'], installationId);
      expect(jsonDecode(request.body), {
        'position': {
          'type': 'Point',
          'coordinates': [5.3698, 43.2965],
        },
        'accuracy_m': 8.0,
        'heading_deg': null,
        'measured_at': '2026-10-05T08:30:00.000Z',
      });

      return http.Response('{"id":"device-1"}', 200);
    });

    await createService(client).sendPosition(
      DevicePosition(
        latitude: 43.2965,
        longitude: 5.3698,
        accuracyM: 8,
        measuredAt: DateTime.utc(2026, 10, 5, 8, 30),
      ),
    );
  });

  test('sendPosition laisse remonter un 404 (appareil inactif)', () async {
    final client = MockClient((request) async {
      return http.Response('{"detail":{"code":"device_not_found"}}', 404);
    });

    await expectLater(
      createService(client).sendPosition(
        DevicePosition(
          latitude: 43.2965,
          longitude: 5.3698,
          accuracyM: 8,
          measuredAt: DateTime.utc(2026, 10, 5, 8, 30),
        ),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('deactivate envoie un DELETE avec l’en-tête d’installation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url,
        Uri.parse('https://api.blueway.test/api/v1/devices/current'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['x-installation-id'], installationId);

      return http.Response('', 204);
    });

    await createService(client).deactivate();
  });
}
