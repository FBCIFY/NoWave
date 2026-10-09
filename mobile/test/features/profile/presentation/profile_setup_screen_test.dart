import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/presentation/profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profileJson = {
  'id': 'user-123',
  'username': 'premier_nom',
  'date_of_birth': null,
  'nationality': null,
  'role': 'user',
  'status': 'active',
  'show_user_name': false,
  'show_boat_info': false,
  'notifications_enabled': false,
  'created_at': '2026-10-07T00:00:00Z',
  'updated_at': '2026-10-07T00:00:00Z',
};

http.Response _error(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': code},
  }),
  status,
);

/// Faux backend : chaque requête reçoit la réponse suivante de sa file.
class _Backend {
  _Backend({required this.posts, this.gets = const []});

  /// Réponses au POST ; une exception simule une réponse perdue.
  final List<Object> posts;
  final List<Object> gets;
  final requests = <String>[];

  late final client = MockClient((request) async {
    requests.add(request.method);
    final queue = request.method == 'POST' ? posts : gets;
    final next = queue.removeAt(0);
    if (next is http.Response) return next;
    throw next;
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _Backend backend, {
  required VoidCallback onProfileCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileSetupScreen(
        profileService: ProfileService(
          apiService: ApiService(
            client: backend.client,
            baseUrl: 'https://api.blueway.test/',
          ),
          getIdToken: () async => 'token',
        ),
        onProfileCreated: onProfileCreated,
        onSignOut: () async {},
      ),
    ),
  );
}

Future<void> _submit(WidgetTester tester, String username) async {
  await tester.enterText(find.byType(TextFormField), username);
  await tester.tap(find.text('Créer mon profil'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'réponse de création perdue, puis 409 : relit le profil et continue',
    (tester) async {
      final backend = _Backend(
        posts: [
          http.ClientException('Connexion interrompue'),
          _error(409, 'user_already_exists'),
        ],
        gets: [http.Response(jsonEncode(_profileJson), 200)],
      );
      var created = 0;
      await _pumpScreen(tester, backend, onProfileCreated: () => created++);

      await _submit(tester, 'premier_nom');
      expect(
        find.text('Impossible de contacter le serveur. Réessayez plus tard.'),
        findsOneWidget,
      );
      expect(created, 0);

      // Le nom saisi au second essai ne compte pas : le profil existe déjà.
      await _submit(tester, 'autre_nom');

      expect(backend.requests, ['POST', 'POST', 'GET']);
      expect(created, 1);
      expect(find.textContaining('existe déjà'), findsNothing);
    },
  );

  testWidgets('409 mais aucun profil relu : erreur, pas de nouvelle création', (
    tester,
  ) async {
    final backend = _Backend(
      posts: [_error(409, 'user_already_exists')],
      gets: [_error(404, 'user_not_found')],
    );
    var created = 0;
    await _pumpScreen(tester, backend, onProfileCreated: () => created++);

    await _submit(tester, 'premier_nom');

    expect(backend.requests, ['POST', 'GET']);
    expect(created, 0);
    expect(
      find.text('Impossible de créer votre profil. Réessayez.'),
      findsOneWidget,
    );
    expect(find.text('Créer mon profil'), findsOneWidget);
  });

  testWidgets('409 puis relecture en échec : erreur, nouvel essai possible', (
    tester,
  ) async {
    final backend = _Backend(
      posts: [
        _error(409, 'user_already_exists'),
        _error(409, 'user_already_exists'),
      ],
      gets: [
        http.ClientException('Connexion interrompue'),
        http.Response(jsonEncode(_profileJson), 200),
      ],
    );
    var created = 0;
    await _pumpScreen(tester, backend, onProfileCreated: () => created++);

    await _submit(tester, 'premier_nom');
    expect(
      find.text(
        'Votre profil existe déjà mais n’a pas pu être chargé. Réessayez.',
      ),
      findsOneWidget,
    );
    expect(created, 0);

    await tester.tap(find.text('Créer mon profil'));
    await tester.pumpAndSettle();

    expect(backend.requests, ['POST', 'GET', 'POST', 'GET']);
    expect(created, 1);
  });

  testWidgets('nom déjà pris : message inchangé, pas de relecture', (
    tester,
  ) async {
    final backend = _Backend(posts: [_error(409, 'username_already_exists')]);
    var created = 0;
    await _pumpScreen(tester, backend, onProfileCreated: () => created++);

    await _submit(tester, 'nom_pris');

    expect(backend.requests, ['POST']);
    expect(created, 0);
    expect(find.text('Ce nom d’utilisateur est déjà utilisé.'), findsOneWidget);
  });

  testWidgets(
    'e-mail lié à un autre profil : message dédié, pas de relecture',
    (tester) async {
      final backend = _Backend(
        posts: [_error(409, 'email_already_registered')],
      );
      var created = 0;
      await _pumpScreen(tester, backend, onProfileCreated: () => created++);

      await _submit(tester, 'nouveau_nom');

      expect(backend.requests, ['POST']);
      expect(created, 0);
      expect(
        find.text(
          'Cette adresse e-mail est déjà liée à un autre compte NoWave. '
          'Connectez-vous avec ce compte.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('création réussie : continue sans relecture', (tester) async {
    final backend = _Backend(
      posts: [http.Response(jsonEncode(_profileJson), 201)],
    );
    var created = 0;
    await _pumpScreen(tester, backend, onProfileCreated: () => created++);

    await _submit(tester, 'premier_nom');

    expect(backend.requests, ['POST']);
    expect(created, 1);
  });
}
