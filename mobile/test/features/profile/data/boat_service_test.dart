import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/domain/boat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const boatJson = {
  'id': 'boat-test',
  'name': 'Aurore',
  'boat_type': 'voilier',
  'flag_country': 'FR',
};

void main() {
  ProfileService service(Future<http.Response> Function(http.Request) handler) {
    final client = MockClient(handler);
    addTearDown(client.close);
    return ProfileService(
      apiService: ApiService(client: client, baseUrl: 'https://nowave.test/'),
      getIdToken: () async => 'test-token',
    );
  }

  test('GET 404 métier représente un bateau absent', () async {
    final api = service((r) async {
      expect(r.url.path, '/api/v1/users/me/boat');
      expect(r.headers['authorization'], 'Bearer test-token');
      return http.Response('{"error":{"code":"boat_not_found"}}', 404);
    });
    expect(await api.getBoat(), isNull);
  });

  for (final code in ['user_not_found', 'route_not_found']) {
    test('GET 404 $code ne devient pas un formulaire de création', () async {
      final api = service(
        (_) async => http.Response('{"error":{"code":"$code"}}', 404),
      );
      await expectLater(api.getBoat(), throwsA(isA<ApiException>()));
    });
  }

  for (final type in BoatType.values) {
    test(
      'POST ${type.apiValue} respecte le contrat et normalise les champs',
      () async {
        final api = service((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/api/v1/users/me/boat');
          expect(jsonDecode(r.body), {
            'boat_type': type.apiValue,
            'name': 'Aurore',
            'flag_country': 'FR',
          });
          return http.Response(
            jsonEncode({...boatJson, 'boat_type': type.apiValue}),
            201,
          );
        });
        expect(
          (await api.saveBoat(
            create: true,
            type: type,
            name: ' Aurore ',
            flagCountry: ' fr ',
          )).type,
          type,
        );
      },
    );
  }

  test('PATCH permet aussi de vider nom et pavillon', () async {
    final api = service((r) async {
      expect(r.method, 'PATCH');
      expect(jsonDecode(r.body), {
        'boat_type': 'catamaran',
        'name': null,
        'flag_country': null,
      });
      return http.Response(
        jsonEncode({
          ...boatJson,
          'boat_type': 'catamaran',
          'name': null,
          'flag_country': null,
        }),
        200,
      );
    });
    expect(
      (await api.saveBoat(
        create: false,
        type: BoatType.catamaran,
        name: ' ',
        flagCountry: '',
      )).name,
      isNull,
    );
  });

  for (final status in [401, 403, 409, 422, 503]) {
    test('POST propage HTTP $status', () async {
      final api = service((_) async => http.Response('{}', status));
      await expectLater(
        api.saveBoat(
          create: true,
          type: BoatType.sailboat,
          name: '',
          flagCountry: '',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', status),
        ),
      );
    });
  }

  for (final account in [false, true]) {
    test(
      'DELETE ${account ? 'compte' : 'bateau'} sans body accepte 204',
      () async {
        final api = service((r) async {
          expect(r.method, 'DELETE');
          expect(
            r.url.path,
            account ? '/api/v1/users/me' : '/api/v1/users/me/boat',
          );
          expect(r.body, isEmpty);
          expect(r.headers['authorization'], 'Bearer test-token');
          return http.Response('', 204);
        });
        await (account ? api.deleteAccount() : api.deleteBoat());
      },
    );
    for (final status in [200, 202, 401, 404, 500]) {
      test('DELETE ${account ? 'compte' : 'bateau'} refuse $status', () async {
        final api = service((_) async => http.Response('{}', status));
        await expectLater(
          account ? api.deleteAccount() : api.deleteBoat(),
          throwsA(anything),
        );
      });
    }
  }

  test('réseau indisponible : erreur conservée', () async {
    final api = service((_) async => throw http.ClientException('offline'));
    await expectLater(api.getBoat(), throwsA(isA<http.ClientException>()));
  });

  testWidgets('réponse perdue : timeout HTTP réel de dix secondes', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = service((_) => response.future);
    final check = expectLater(
      api.deleteAccount(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await check;
    response.complete(http.Response('', 204));
    await tester.pump();
  });
}
