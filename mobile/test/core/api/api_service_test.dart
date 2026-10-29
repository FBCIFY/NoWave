import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:async';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_config.dart';

void main() {
  test(
    'environnement : client métier et token restent sur API_BASE_URL',
    () async {
      if (ApiConfig.baseUrl.isEmpty) return;
      final paths = [
        'api/v1/users/me',
        'api/v1/reports',
        'api/v1/photos',
        'api/v1/alerts',
        'api/v1/map/tiles/12/2115/1503.mvt',
        'api/v1/map/another-feature',
      ];
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = ApiService(client: client);
      for (final path in paths) {
        await api.get(path, headers: {'Authorization': 'Bearer unit-token'});
      }
      expect(requests, hasLength(paths.length));
      for (var i = 0; i < paths.length; i++) {
        expect(requests[i].url, ApiConfig.resolve(paths[i]));
        expect(requests[i].headers['authorization'], 'Bearer unit-token');
      }
    },
  );

  test(
    'base sans slash, préfixe et paramètres conservés dans le client',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.com/proxy/api/v1/users/me?tenant=eu&detail=full',
        );
        expect(request.headers['authorization'], 'Bearer unit-token');
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = ApiService(
        client: client,
        baseUrl: 'https://api.example.com/proxy?tenant=eu',
      );
      await api.get(
        '/api/v1/users/me?detail=full',
        headers: {'Authorization': 'Bearer unit-token'},
      );
    },
  );

  test(
    'un chemin absolu ne peut transmettre le token à un fournisseur',
    () async {
      var sent = false;
      final client = MockClient((request) async {
        sent = true;
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final api = ApiService(
        client: client,
        baseUrl: 'https://api.example.com/',
      );
      await expectLater(
        api.get(
          'https://api.mapbox.com/tiles',
          headers: {'Authorization': 'Bearer unit-token'},
        ),
        throwsArgumentError,
      );
      expect(sent, isFalse);
    },
  );

  test('get retourne le contenu pour une réponse HTTP 200', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://example.com/reports'));

      return http.Response('Réponse de test', 200);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final result = await api.get('reports');

    expect(result, 'Réponse de test');
  });

  test('post transmet le jeton et le contenu JSON', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://example.com/api/v1/users/me'));
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['content-type'], 'application/json');
      expect(request.body, '{"username":"Vadim"}');

      return http.Response('{"username":"Vadim"}', 201);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final result = await api.post(
      'api/v1/users/me',
      headers: {
        'Authorization': 'Bearer firebase-token',
        'Content-Type': 'application/json',
      },
      body: '{"username":"Vadim"}',
    );

    expect(result, '{"username":"Vadim"}');
  });

  test('patch transmet le jeton et les champs modifiés', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url, Uri.parse('https://example.com/api/v1/users/me'));
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['content-type'], 'application/json');
      expect(request.body, '{"notifications_enabled":true}');

      return http.Response('{"notifications_enabled":true}', 200);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final result = await api.patch(
      'api/v1/users/me',
      headers: {
        'Authorization': 'Bearer firebase-token',
        'Content-Type': 'application/json',
      },
      body: '{"notifications_enabled":true}',
    );

    expect(result, '{"notifications_enabled":true}');
  });

  test('put transmet le jeton et le contenu JSON', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(
        request.url,
        Uri.parse('https://example.com/api/v1/devices/current'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token');
      expect(request.headers['content-type'], 'application/json');
      expect(request.body, '{"platform":"ios"}');

      return http.Response('{"platform":"ios"}', 200);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final result = await api.put(
      'api/v1/devices/current',
      headers: {
        'Authorization': 'Bearer firebase-token',
        'Content-Type': 'application/json',
      },
      body: '{"platform":"ios"}',
    );

    expect(result, '{"platform":"ios"}');
  });

  test('delete accepte une réponse 204 sans contenu', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url,
        Uri.parse('https://example.com/api/v1/devices/current'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token');

      return http.Response('', 204);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final result = await api.delete(
      'api/v1/devices/current',
      headers: {'Authorization': 'Bearer firebase-token'},
    );

    expect(result, isEmpty);
  });

  test('get lève une exception pour une réponse HTTP 500', () async {
    final client = MockClient((request) async {
      return http.Response('Erreur serveur', 500);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    await expectLater(
      api.get('reports'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.body, 'body', 'Erreur serveur'),
      ),
    );
  });

  test('get refuse une URL invalide sans requête HTTP', () async {
    var requestSent = false;

    final client = MockClient((request) async {
      requestSent = true;
      return http.Response('Réponse inattendue', 200);
    });

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'adresse-invalide');

    await expectLater(api.get('reports'), throwsA(isA<StateError>()));

    expect(requestSent, isFalse);
  });

  testWidgets('get expire après 10 secondes sans réponse', (tester) async {
    final response = Completer<http.Response>();
    final client = MockClient((request) => response.future);

    addTearDown(client.close);

    final api = ApiService(client: client, baseUrl: 'https://example.com/');

    final verification = expectLater(
      api.get('reports'),
      throwsA(isA<TimeoutException>()),
    );

    await tester.pump(const Duration(seconds: 10));
    await verification;
  });

  test('403 user_inactive notifie la suspension', () async {
    var inactiveCalls = 0;

    final client = MockClient((request) async {
      return http.Response(
        '{"error":{"code":"user_inactive","message":"user is not active","details":null}}',
        403,
      );
    });

    addTearDown(client.close);

    final api = ApiService(
      client: client,
      baseUrl: 'https://example.com/',
      onUserInactive: () {
        inactiveCalls++;
      },
    );

    await expectLater(
      api.get('reports'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'user_inactive',
        ),
      ),
    );

    expect(inactiveCalls, 1);
  });

  test('ApiException lit le contrat d’erreur NoWave', () {
    const error = ApiException(
      statusCode: 404,
      body: '''
{
  "error": {
    "code": "user_not_found",
    "message": "User not found",
    "details": null
  }
}
''',
    );

    expect(error.code, 'user_not_found');
    expect(error.message, 'User not found');
    expect(error.details, isNull);
  });
}
