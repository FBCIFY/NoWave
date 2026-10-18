import 'package:blueway/core/api/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final base in [
    'https://api.example.com',
    'https://api.example.com/',
    'https://api.example.com///',
  ]) {
    test('base valide et slashs : $base', () {
      expect(
        ApiConfig.endpoint('api/v1/users/me', baseUrl: base),
        'https://api.example.com/api/v1/users/me',
      );
    });
  }

  for (final base in [
    '',
    ' ',
    'backend-invalide',
    '/backend',
    'ftp://api.example.com',
    'https://',
    'https://bad host/',
    'https://api.example.com:99999',
    'https://user:secret@api.example.com/',
    'https://api.example.com/#fragment',
  ]) {
    test('configuration invalide refusée sans fallback : ${base.length}', () {
      expect(
        () => ApiConfig.resolve('api/v1/users/me', baseUrl: base),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('API_BASE_URL'),
          ),
        ),
      );
    });
  }

  test('HTTP, port et préfixe conservés même avec un chemin /api', () {
    expect(
      ApiConfig.endpoint(
        '/api/v1/reports',
        baseUrl: 'http://127.0.0.1:8004/gateway',
      ),
      'http://127.0.0.1:8004/gateway/api/v1/reports',
    );
  });

  test('préfixe encodé, paramètres multiples et version conservés', () {
    expect(
      ApiConfig.endpoint(
        'api/v1/map/seamarks/{z}/{x}/{y}.pbf?tag=a&tag=b',
        baseUrl: 'https://api.example.com/a%20b/?tenant=eu',
        queryParameters: {'v': '3'},
      ),
      'https://api.example.com/a%20b/api/v1/map/seamarks/{z}/{x}/{y}.pbf'
      '?tenant=eu&tag=a&tag=b&v=3',
    );
  });

  for (final path in [
    'https://api.mapbox.com/api/v1/reports',
    '//services.data.shom.fr/api/v1/reports',
    '../api/v1/reports',
    '%2e%2e/api/v1/reports',
  ]) {
    test('un appel ne peut sortir du backend : $path', () {
      expect(
        () =>
            ApiConfig.resolve(path, baseUrl: 'https://api.example.com/proxy/'),
        throwsArgumentError,
      );
    });
  }

  for (final family in [
    'bathymetry',
    'depth-contours',
    'soundings',
    'underwater-hazards',
    'seamarks',
    'port-infrastructure',
    'tiles',
  ]) {
    test('template Mapbox réel : $family', () {
      final extension = family == 'bathymetry'
          ? 'png'
          : family == 'tiles'
          ? 'mvt'
          : 'pbf';
      final result = ApiConfig.tileTemplate(
        family,
        extension: extension,
        baseUrl: 'https://api.example.com/proxy',
      );
      expect(
        result,
        'https://api.example.com/proxy/api/v1/map/$family/{z}/{x}/{y}.$extension',
      );
      expect(result, isNot(contains('%7B')));
    });
  }

  test('version du cache remplace v et garde les autres paramètres et XYZ', () {
    expect(
      ApiConfig.withQueryParameters(
        'https://api.example.com/{z}/{x}/{y}.png?region=eu&v=old',
        {'v': 'coast-1'},
      ),
      'https://api.example.com/{z}/{x}/{y}.png?region=eu&v=coast-1',
    );
  });
}
