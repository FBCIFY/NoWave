import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/core/api/api_exception.dart';

void main() {
  const profileJson = {
    'id': 'user-123',
    'username': 'vadim',
    'date_of_birth': null,
    'nationality': null,
    'role': 'user',
    'status': 'active',
    'show_user_name': false,
    'show_boat_info': false,
    'notifications_enabled': false,
    'created_at': '2026-09-22T00:00:00Z',
    'updated_at': '2026-09-22T00:00:00Z',
  };

  ProfileService createService(http.Client client) {
    return ProfileService(
      apiService: ApiService(
        client: client,
        baseUrl: 'https://api.blueway.test/',
      ),
      getIdToken: () async => 'firebase-token-de-test',
    );
  }

  test('récupère le profil courant avec le token Firebase', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(
        request.url,
        Uri.parse('https://api.blueway.test/api/v1/users/me'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token-de-test');

      return http.Response(jsonEncode(profileJson), 200);
    });

    final profile = await createService(client).getCurrentProfile();

    expect(profile, isNotNull);
    expect(profile!.username, 'vadim');
    expect(profile.role, 'user');
    expect(profile.showUserName, isFalse);
  });

  test('retourne null lorsque le profil n’existe pas', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'code': 'USER_NOT_FOUND'}), 404);
    });

    final profile = await createService(client).getCurrentProfile();

    expect(profile, isNull);
  });

  test('crée le profil avec le nom utilisateur', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer firebase-token-de-test');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {'username': 'vadim'});

      return http.Response(jsonEncode(profileJson), 201);
    });

    final profile = await createService(client)
        .createProfile(username: '  vadim  ');

    expect(profile.username, 'vadim');
  });

  test('met à jour uniquement la préférence modifiée', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(
        request.url,
        Uri.parse('https://api.blueway.test/api/v1/users/me'),
      );
      expect(request.headers['authorization'], 'Bearer firebase-token-de-test');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {'notifications_enabled': true});

      return http.Response(
        jsonEncode({...profileJson, 'notifications_enabled': true}),
        200,
      );
    });

    final profile = await createService(client)
        .updatePreferences(notificationsEnabled: true);

    expect(profile.notificationsEnabled, isTrue);
    expect(profile.showUserName, isFalse);
  });

  test('refuse une mise à jour sans préférence', () async {
    final client = MockClient((request) async {
      fail('Aucune requête ne doit être envoyée.');
    });

    expect(
      () => createService(client).updatePreferences(),
      throwsArgumentError,
    );
  });

  test('propage l’erreur du serveur lors de la mise à jour', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'code': 'VALIDATION_ERROR'}), 422);
    });

    await expectLater(
      createService(client).updatePreferences(showBoatInfo: true),
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
