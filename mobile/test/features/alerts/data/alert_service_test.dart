import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/alert_fixtures.dart';

void main() {
  AlertService service(Future<http.Response> Function(http.Request) respond) {
    final client = MockClient(respond);
    addTearDown(client.close);
    return AlertService(
      apiService: ApiService(client: client, baseUrl: 'https://nowave.test/'),
      getIdToken: () async => 'test-token',
    );
  }

  test(
    'GET historique authentifié et page demandée, longitude avant latitude',
    () async {
      final api = service((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/users/me/alerts');
        expect(request.url.queryParameters, {'page': '2', 'limit': '20'});
        expect(request.headers['authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode(pageJson(page: 2, pages: 2, total: 21)),
          200,
        );
      });
      final page = await api.fetchPage(page: 2);
      expect(page.items.single.longitude, 5.37);
      expect(page.items.single.latitude, 43.29);
      expect(page.items.single.positionDms, contains('43°'));
      expect(page.total, 21);
    },
  );

  for (final count in [0, 1, 3]) {
    test('historique $count alertes', () async {
      final api = service(
        (_) async => http.Response(
          jsonEncode(
            pageJson(
              items: List.generate(
                count,
                (i) => alertJson(id: 'a$i', reportId: 'r$i'),
              ),
              total: count,
              pages: count == 0 ? 0 : 1,
            ),
          ),
          200,
        ),
      );
      expect((await api.fetchPage()).items, hasLength(count));
    });
  }
  for (final status in [401, 403, 404, 422, 500, 503]) {
    test('HTTP $status reste une erreur, jamais un historique vide', () async {
      final api = service((_) async => http.Response('{}', status));
      await expectLater(
        api.fetchPage(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'HTTP', status),
        ),
      );
    });
  }
  test('réseau indisponible', () async {
    final api = service((_) async => throw http.ClientException('offline'));
    await expectLater(api.fetchPage(), throwsA(isA<http.ClientException>()));
  });
  test('page inattendue refusée', () async {
    final api = service(
      (_) async => http.Response(jsonEncode(pageJson()), 200),
    );
    await expectLater(api.fetchPage(page: 2), throwsFormatException);
  });
  testWidgets('délai HTTP réel de dix secondes', (tester) async {
    final response = Completer<http.Response>();
    final api = service((_) => response.future);
    final check = expectLater(
      api.fetchPage(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await check;
    response.complete(http.Response(jsonEncode(pageJson()), 200));
    await tester.pump();
  });
  for (final changes in <Map<String, dynamic>>[
    {'report_version': 0},
    {'category': 'unknown'},
    {'distance_m': -1},
    {
      'position': {
        'type': 'Point',
        'coordinates': [190, 90],
      },
    },
    {
      'position': {
        'type': 'Point',
        'coordinates': [5, double.nan],
      },
    },
    {
      'position': {
        'type': 'LineString',
        'coordinates': [5, 43],
      },
    },
    {'id': ''},
    {'alerted_at': 'not-a-date'},
  ]) {
    test('alerte invalide refusée : $changes', () {
      expect(
        () => Alert.fromJson({...alertJson(), ...changes}),
        throwsFormatException,
      );
    });
  }
  test('push exige position_dms', () {
    expect(
      () => AlertPush.fromData(pushData()..remove('position_dms')),
      throwsFormatException,
    );
  });
  for (final value in <Object?>[
    null,
    42,
    '',
    '   ',
    'not-dms',
    '43° 60′ 24″ N · 5° 22′ 12″ E',
    '43° 17′ 60″ N · 5° 22′ 12″ E',
    '91° 0′ 0″ N · 5° 22′ 12″ E',
    '90° 0′ 1″ N · 5° 22′ 12″ E',
    '43° 17′ 24″ N · 181° 0′ 0″ E',
    '43° 17′ 24″ S · 5° 22′ 12″ E',
    '43° 17′ 24″ N · 5° 22′ 12″ W',
    '43° 17′ 25″ N · 5° 22′ 12″ E',
  ]) {
    test('DMS invalide ou incohérent refusé : $value', () {
      expect(
        () => AlertPush.fromData({...pushData(), 'position_dms': value}),
        throwsFormatException,
      );
    });
  }
  test('DMS cohérent, hémisphères sud/ouest et arrondi', () {
    final push = AlertPush.fromData({
      ...pushData(),
      'position': jsonEncode({
        'type': 'Point',
        'coordinates': [-5.3701, -43.2901],
      }),
      'position_dms': '43° 17′ 24″ S · 5° 22′ 12″ W',
    });
    expect(push.positionDms, push.alert.positionDms);
  });
  test('DMS avec quotes ASCII, virgule et secondes décimales', () {
    final push = AlertPush.fromData({
      ...pushData(),
      'position_dms': """43°17'24.0"N, 5°22'12.0"E""",
    });
    expect(push.alert.latitude, 43.29);
  });
  test('DMS cohérent aux limites géographiques', () {
    final push = AlertPush.fromData({
      ...pushData(),
      'position': jsonEncode({
        'type': 'Point',
        'coordinates': [180, 90],
      }),
      'position_dms': '90° 0′ 0″ N · 180° 0′ 0″ E',
    });
    expect(push.positionDms, push.alert.positionDms);
  });

  test('push sans date d’alerte accepté sans inventer de date', () {
    final data = pushData()..remove('alerted_at');
    expect(AlertPush.fromData(data).alert.alertedAt, isNull);
    expect(
      () => Alert.fromJson(alertJson()..remove('alerted_at')),
      throwsFormatException,
    );
  });

  test(
    'payload FCM transporte identifiants, version, DMS, distance et expiration',
    () {
      final push = AlertPush.fromData(pushData(), messageId: 'message');
      expect(push.alert.reportId, 'report-a');
      expect(push.alert.version, 1);
      expect(push.positionDms, '43° 17′ 24″ N · 5° 22′ 12″ E');
      expect(push.positionDms, push.alert.positionDms);
      expect(push.alert.id, 'alert-a');
      expect(push.messageId, 'message');
      expect(push.alert.distanceM, 3334);
      expect(push.expired(testNow), isFalse);
      expect(push.expired(push.expiresAt), isTrue);
    },
  );
}
