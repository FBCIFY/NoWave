import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:async';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/api/api_exception.dart';

void main() {
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
