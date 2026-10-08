import 'dart:convert';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Réponse complète du backend, modifiable par test.
Map<String, Object?> _detailJson() => {
  'id': '550e8400-e29b-41d4-a716-446655440000',
  'version': 1,
  'category': 'marine_animal',
  'description': 'Dauphins',
  'positioning_mode': 'photo',
  'final_position': {
    'type': 'Point',
    'coordinates': [5.123456, 43.123456],
  },
  'status': 'active',
  'observed_at': '2026-10-05T09:30:00Z',
  'expires_at': '2026-10-05T15:30:00Z',
  'author': {'username': 'marin', 'deleted': false},
  'boat': {'name': 'Albatros', 'boat_type': 'semi_rigide'},
  'photo': {'status': 'pending', 'url': null},
};

/// Service branché sur un faux client qui répond [status] et [body].
ReportDetailService _service(
  int status,
  Object body, {
  void Function(http.Request request)? onRequest,
}) => ReportDetailService(
  apiService: ApiService(
    client: MockClient((request) async {
      onRequest?.call(request);
      return http.Response(jsonEncode(body), status);
    }),
    baseUrl: 'https://api.blueway.test/',
  ),
  getIdToken: () async => 'firebase-token',
);

void main() {
  test('lit la fiche authentifiée au contrat backend', () async {
    final service = _service(
      200,
      _detailJson(),
      onRequest: (request) {
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse(
            'https://api.blueway.test/api/v1/reports/'
            '550e8400-e29b-41d4-a716-446655440000',
          ),
        );
        expect(request.headers['authorization'], 'Bearer firebase-token');
      },
    );

    final report = await service.fetchReport(
      '550e8400-e29b-41d4-a716-446655440000',
    );

    expect(report.id, '550e8400-e29b-41d4-a716-446655440000');
    expect(report.category, ReportCategory.marineAnimal);
    expect(report.description, 'Dauphins');
    // GeoJSON : [longitude, latitude].
    expect(report.latitude, 43.123456);
    expect(report.longitude, 5.123456);
    expect(report.observedAt, DateTime.utc(2026, 10, 5, 9, 30));
    expect(report.expiresAt, DateTime.utc(2026, 10, 5, 15, 30));
    expect(report.author?.username, 'marin');
    expect(report.author?.deleted, isFalse);
    expect(report.boat?.name, 'Albatros');
    expect(report.boat?.type, BoatType.rib);
    expect(report.photo?.status, ReportPhotoStatus.pending);
    expect(report.photo?.url, isNull);
  });

  test('accepte un auteur supprimé et les infos cachées', () async {
    final json = _detailJson()
      ..['description'] = null
      ..['author'] = {'username': null, 'deleted': true}
      ..['boat'] = null
      ..['photo'] = null;

    final report = await _service(200, json).fetchReport('id');

    expect(report.description, isNull);
    expect(report.author?.username, isNull);
    expect(report.author?.deleted, isTrue);
    expect(report.boat, isNull);
    expect(report.photo, isNull);
  });

  test('accepte un auteur qui cache son nom', () async {
    final json = _detailJson()..['author'] = null;

    final report = await _service(200, json).fetchReport('id');

    expect(report.author, isNull);
  });

  test('traduit le 404 en signalement plus disponible', () async {
    final service = _service(404, {
      'error': {
        'code': 'report_not_found',
        'message': 'report not found',
        'details': null,
      },
    });

    await expectLater(
      service.fetchReport('id'),
      throwsA(isA<ReportNotFoundException>()),
    );
  });

  test('laisse passer les autres erreurs HTTP', () async {
    final service = _service(401, {
      'error': {'code': 'unauthorized', 'message': 'nope', 'details': null},
    });

    await expectLater(
      service.fetchReport('id'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('refuse une catégorie inconnue', () async {
    final json = _detailJson()..['category'] = 'kraken';

    await expectLater(
      _service(200, json).fetchReport('id'),
      throwsFormatException,
    );
  });

  group('fetchPhoto', () {
    ReportDetailService photoService(MockClientHandler handler) =>
        ReportDetailService(
          apiService: ApiService(
            client: MockClient((_) async => fail('appel backend inattendu')),
            baseUrl: 'https://api.blueway.test/',
          ),
          getIdToken: () async => 'firebase-token',
          photoClient: MockClient(handler),
        );

    test('télécharge l’URL signée telle quelle, sans token', () async {
      const url = 'https://s3.test/reports/a.jpg?X-Amz-Signature=abc';
      final service = photoService((request) async {
        expect(request.url, Uri.parse(url));
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response.bytes([1, 2, 3], 200);
      });

      expect(await service.fetchPhoto(url), [1, 2, 3]);
    });

    test('lève une ApiException 403 si le stockage refuse', () async {
      final service = photoService(
        (_) async => http.Response('<Error>AccessDenied</Error>', 403),
      );

      await expectLater(
        service.fetchPhoto('https://s3.test/a.jpg'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });
}
