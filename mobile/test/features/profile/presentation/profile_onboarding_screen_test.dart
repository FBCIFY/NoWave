import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/auth/presentation/widgets/auth_primary_button.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/domain/user_profile.dart';
import 'package:blueway/features/profile/presentation/profile_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../core/notifications/fake_notification_permission_service.dart';

const _profileJson = {
  'id': 'user-123',
  'username': 'Marin',
  'date_of_birth': null,
  'nationality': null,
  'role': 'user',
  'status': 'active',
  'show_user_name': false,
  'show_boat_info': false,
  'notifications_enabled': false,
  'created_at': '2026-10-20T00:00:00Z',
  'updated_at': '2026-10-20T00:00:00Z',
};

final _profile = UserProfile.fromJson(_profileJson);

http.Response _error(int status, String code) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': code},
  }),
  status,
);

/// Faux backend et faux enregistrement des préférences.
class _Harness {
  _Harness(this.responses);

  /// Réponses du backend, dans l'ordre des requêtes ; une exception simule
  /// une réponse perdue. Une fois la file vide, le backend renvoie ce qu'il
  /// a reçu.
  final List<Object> responses;
  final requests = <http.Request>[];
  final saved = <UserProfile>[];
  final preferences = <Map<String, bool>>[];
  final permissions = FakeNotificationPermissionService();
  Object? preferencesFailure;
  var done = 0;

  List<String> get methods => [for (final r in requests) r.method];

  http.Response echo(http.Request request) {
    final created = request.method == 'POST' ? 201 : 200;
    if (request.url.path.endsWith('/boat')) {
      return http.Response(
        jsonEncode({'id': 'boat-1', ...jsonDecode(request.body) as Map}),
        created,
      );
    }
    return http.Response(
      jsonEncode({
        ..._profileJson,
        if (request.method != 'GET') ...jsonDecode(request.body) as Map,
      }),
      created,
    );
  }
}

/// [newAccount] : pas encore de profil, le parcours commence au nom.
Future<_Harness> _open(
  WidgetTester tester, {
  List<Object>? responses,
  UserProfile? profile,
  bool newAccount = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final harness = _Harness(responses ?? []);
  final current = newAccount ? null : profile ?? _profile;
  final client = MockClient((request) async {
    harness.requests.add(request);
    if (harness.responses.isEmpty) return harness.echo(request);
    final next = harness.responses.removeAt(0);
    if (next is http.Response) return next;
    throw next;
  });
  addTearDown(client.close);

  await tester.pumpWidget(
    MaterialApp(
      home: ProfileOnboardingScreen(
        profile: current,
        profileService: ProfileService(
          apiService: ApiService(
            client: client,
            baseUrl: 'https://api.blueway.test/',
          ),
          getIdToken: () async => 'token',
        ),
        onProfileSaved: harness.saved.add,
        onUpdatePreferences:
            ({showUserName, showBoatInfo, notificationsEnabled}) async {
              harness.preferences.add({
                'show_user_name': ?showUserName,
                'show_boat_info': ?showBoatInfo,
                'notifications_enabled': ?notificationsEnabled,
              });
              if (harness.preferencesFailure case final failure?) {
                throw failure;
              }
              return (current ?? _profile).copyWith(
                showUserName: showUserName,
                showBoatInfo: showBoatInfo,
                notificationsEnabled: notificationsEnabled,
              );
            },
        notificationPermissions: harness.permissions,
        onSignOut: () async {},
        onDone: () => harness.done++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Retour'));
  await tester.pumpAndSettle();
}

Future<void> _submitUsername(WidgetTester tester, String username) async {
  await tester.enterText(find.byType(TextFormField), username);
  await tester.tap(find.byType(AuthPrimaryButton));
  await tester.pumpAndSettle();
}

/// Choisit un type puis ouvre la page du nom et du pavillon.
Future<void> _chooseType(WidgetTester tester, String type) async {
  await _tap(tester, type);
  await _tap(tester, 'Suivant');
  expect(find.text('Nom et pavillon'), findsOneWidget);
}

/// Passe le bateau et la visibilité sans rien changer.
Future<void> _skipToAlerts(WidgetTester tester) async {
  await _tap(tester, 'Je n’ai pas de bateau');
  await _tap(tester, 'Continuer');
  expect(find.text('Alertes à proximité'), findsOneWidget);
  expect(find.text('ÉTAPE 5 SUR 5'), findsOneWidget);
}

void main() {
  group('nom d’utilisateur', () {
    testWidgets('crée le profil puis passe au bateau', (tester) async {
      final harness = await _open(tester, newAccount: true);
      expect(find.text('ÉTAPE 1 SUR 5'), findsOneWidget);
      expect(find.byTooltip('Retour'), findsNothing);

      // Majuscule au début ; espaces du bord retirés, ceux du milieu gardés.
      await tester.enterText(find.byType(TextFormField), '  jean  marin  ');
      expect(find.text('  Jean  marin  '), findsOneWidget);
      await _tap(tester, 'Créer mon profil');

      expect(harness.methods, ['POST']);
      expect(jsonDecode(harness.requests.single.body), {
        'username': 'Jean  marin',
      });
      expect(harness.saved.single.username, 'Jean  marin');
      expect(find.text('ÉTAPE 2 SUR 5'), findsOneWidget);
      expect(find.text('Votre bateau'), findsOneWidget);
    });

    testWidgets('un nom composé uniquement d’espaces reste refusé', (
      tester,
    ) async {
      final harness = await _open(tester, newAccount: true);
      await _submitUsername(tester, '   ');
      expect(harness.requests, isEmpty);
      expect(find.text('Choisissez un nom d’utilisateur.'), findsOneWidget);
    });

    testWidgets(
      'réponse de création perdue, puis 409 : relit le profil et continue',
      (tester) async {
        final harness = await _open(
          tester,
          newAccount: true,
          responses: [
            http.ClientException('Connexion interrompue'),
            _error(409, 'user_already_exists'),
            http.Response(jsonEncode(_profileJson), 200),
          ],
        );

        await _submitUsername(tester, 'Marin');
        expect(
          find.text('Impossible de contacter le serveur. Réessayez plus tard.'),
          findsOneWidget,
        );
        expect(harness.saved, isEmpty);

        // Le nom saisi au second essai ne compte pas : le profil existe déjà.
        await _submitUsername(tester, 'Autre_nom');

        expect(harness.methods, ['POST', 'POST', 'GET']);
        expect(harness.saved.single.username, 'Marin');
        expect(find.text('Votre bateau'), findsOneWidget);
        expect(find.textContaining('existe déjà'), findsNothing);

        // En revenant, le champ montre le nom enregistré.
        await _back(tester);
        expect(find.text('Marin'), findsOneWidget);
      },
    );

    testWidgets(
      '409 mais aucun profil relu : erreur, pas de nouvelle création',
      (tester) async {
        final harness = await _open(
          tester,
          newAccount: true,
          responses: [
            _error(409, 'user_already_exists'),
            _error(404, 'user_not_found'),
          ],
        );

        await _submitUsername(tester, 'Marin');

        expect(harness.methods, ['POST', 'GET']);
        expect(harness.saved, isEmpty);
        expect(
          find.text('Impossible de créer votre profil. Réessayez.'),
          findsOneWidget,
        );
        expect(find.text('Créer mon profil'), findsOneWidget);
      },
    );

    testWidgets('409 puis relecture en échec : erreur, nouvel essai possible', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        newAccount: true,
        responses: [
          _error(409, 'user_already_exists'),
          http.ClientException('Connexion interrompue'),
          _error(409, 'user_already_exists'),
          http.Response(jsonEncode(_profileJson), 200),
        ],
      );

      await _submitUsername(tester, 'Marin');
      expect(
        find.text(
          'Votre profil existe déjà mais n’a pas pu être chargé. Réessayez.',
        ),
        findsOneWidget,
      );
      expect(harness.saved, isEmpty);

      await _tap(tester, 'Créer mon profil');

      expect(harness.methods, ['POST', 'GET', 'POST', 'GET']);
      expect(harness.saved, hasLength(1));
    });

    testWidgets('nom déjà pris : message, pas de relecture', (tester) async {
      final harness = await _open(
        tester,
        newAccount: true,
        responses: [_error(409, 'username_already_exists')],
      );

      await _submitUsername(tester, 'Nom_pris');

      expect(harness.methods, ['POST']);
      expect(harness.saved, isEmpty);
      expect(
        find.text('Ce nom d’utilisateur est déjà utilisé.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'e-mail lié à un autre profil : message dédié, pas de relecture',
      (tester) async {
        final harness = await _open(
          tester,
          newAccount: true,
          responses: [_error(409, 'email_already_registered')],
        );

        await _submitUsername(tester, 'Nouveau_nom');

        expect(harness.methods, ['POST']);
        expect(harness.saved, isEmpty);
        expect(
          find.text(
            'Cette adresse e-mail est déjà liée à un autre profil NoWave. '
            'Contactez le support.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('retour au nom : inchangé sans requête, changé par un PATCH', (
      tester,
    ) async {
      final harness = await _open(tester, newAccount: true);
      await _submitUsername(tester, 'Marin');
      expect(harness.methods, ['POST']);

      // Retour Android depuis le bateau.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('ÉTAPE 1 SUR 5'), findsOneWidget);
      expect(find.text('Marin'), findsOneWidget);
      expect(find.text('Créer mon profil'), findsNothing);

      await _tap(tester, 'Suivant');
      expect(find.text('Votre bateau'), findsOneWidget);
      expect(harness.methods, ['POST']);

      await _back(tester);
      harness.responses.add(_error(409, 'username_already_exists'));
      await _submitUsername(tester, 'Nom_pris');
      expect(
        find.text('Ce nom d’utilisateur est déjà utilisé.'),
        findsOneWidget,
      );
      expect(find.text('ÉTAPE 1 SUR 5'), findsOneWidget);

      await _submitUsername(tester, 'Capitaine');
      expect(harness.methods, ['POST', 'PATCH', 'PATCH']);
      expect(harness.requests.last.url.path, '/api/v1/users/me');
      expect(jsonDecode(harness.requests.last.body), {'username': 'Capitaine'});
      expect(
        [for (final p in harness.saved) p.username],
        ['Marin', 'Capitaine'],
      );
      expect(find.text('Votre bateau'), findsOneWidget);
    });
  });

  group('bateau et visibilité', () {
    testWidgets('sans bateau : aucune requête et pas de choix pour le bateau', (
      tester,
    ) async {
      final harness = await _open(tester);
      expect(find.text('ÉTAPE 2 SUR 5'), findsOneWidget);
      expect(find.text('Votre bateau'), findsOneWidget);

      await _tap(tester, 'Je n’ai pas de bateau');
      expect(find.text('ÉTAPE 4 SUR 5'), findsOneWidget);
      expect(find.text('Afficher mon nom d’utilisateur'), findsOneWidget);
      expect(find.text('Afficher mon bateau'), findsNothing);

      await _tap(tester, 'Continuer');
      expect(find.text('Alertes à proximité'), findsOneWidget);
      expect(harness.requests, isEmpty);
      expect(harness.preferences, isEmpty);
      expect(harness.done, 0);
    });

    testWidgets('« Suivant » reste inactif tant qu’aucun type n’est choisi', (
      tester,
    ) async {
      await _open(tester);

      await _tap(tester, 'Suivant');
      expect(find.text('Votre bateau'), findsOneWidget);
      expect(find.text('Nom et pavillon'), findsNothing);

      await _chooseType(tester, 'Catamaran');
      expect(find.text('ÉTAPE 3 SUR 5'), findsOneWidget);
    });

    testWidgets('enregistre le bateau puis les choix de visibilité', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _chooseType(tester, 'Catamaran');

      await tester.enterText(find.byType(TextFormField).first, 'belle Île');
      await tester.enterText(find.byType(TextFormField).last, 'fr');
      expect(find.text('Belle Île'), findsOneWidget);
      expect(find.text('FR'), findsOneWidget);
      await _tap(tester, 'Suivant');

      expect(harness.methods, ['POST']);
      expect(harness.requests.single.url.path, '/api/v1/users/me/boat');
      expect(jsonDecode(harness.requests.single.body), {
        'boat_type': 'catamaran',
        'name': 'Belle Île',
        'flag_country': 'FR',
      });

      expect(find.text('Sur vos signalements'), findsOneWidget);
      // Toute la carte bascule l'interrupteur.
      await _tap(tester, 'Afficher mon nom d’utilisateur');
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      await _tap(tester, 'Continuer');
      expect(harness.preferences, [
        {'show_user_name': true, 'show_boat_info': true},
      ]);
      expect(find.text('Alertes à proximité'), findsOneWidget);

      // En revenant, les choix enregistrés restent affichés et ne sont pas
      // renvoyés.
      await _back(tester);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value),
        [true, true],
      );
      await _tap(tester, 'Continuer');
      expect(harness.preferences, hasLength(1));
      expect(find.text('Alertes à proximité'), findsOneWidget);
    });

    testWidgets('un pavillon d’une seule lettre est signalé sans requête', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _chooseType(tester, 'Voilier');

      await tester.enterText(find.byType(TextFormField).last, 'f1');
      expect(find.text('F'), findsOneWidget);
      await _tap(tester, 'Suivant');

      expect(
        find.text(
          'Le pavillon est un code pays de deux lettres, par exemple FR.',
        ),
        findsOneWidget,
      );
      expect(harness.requests, isEmpty);
    });

    testWidgets('échec de l’enregistrement : message puis « Passer »', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        responses: [http.Response('{}', 503)],
      );
      await _chooseType(tester, 'Voilier');
      expect(find.text('Passer'), findsNothing);

      await _tap(tester, 'Suivant');
      expect(
        find.textContaining('Le bateau n’a pas pu être enregistré'),
        findsOneWidget,
      );

      await _tap(tester, 'Passer');
      expect(find.text('Sur vos signalements'), findsOneWidget);
      expect(find.text('Afficher mon bateau'), findsNothing);

      await _tap(tester, 'Continuer');
      expect(harness.methods, ['POST']);
      expect(find.text('Alertes à proximité'), findsOneWidget);
    });

    testWidgets(
      'réponse de création perdue, puis 409 : met à jour le bateau existant',
      (tester) async {
        final harness = await _open(
          tester,
          responses: [
            http.ClientException('Connexion interrompue'),
            _error(409, 'boat_already_exists'),
          ],
        );
        await _chooseType(tester, 'Jet-ski');

        await _tap(tester, 'Suivant');
        expect(
          find.textContaining('Le bateau n’a pas pu être enregistré'),
          findsOneWidget,
        );

        await _tap(tester, 'Suivant');
        expect(harness.methods, ['POST', 'POST', 'PATCH']);
        expect(find.text('Afficher mon bateau'), findsOneWidget);
      },
    );

    testWidgets('retour : un bateau déjà créé est mis à jour, pas recréé', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _chooseType(tester, 'Voilier');
      await _tap(tester, 'Suivant');
      expect(find.text('Sur vos signalements'), findsOneWidget);

      await _back(tester);
      expect(find.text('Nom et pavillon'), findsOneWidget);

      // Retour Android.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Votre bateau'), findsOneWidget);
      // Le bateau existe : il se supprime depuis le profil.
      expect(find.text('Je n’ai pas de bateau'), findsNothing);

      await _chooseType(tester, 'Catamaran');
      await _tap(tester, 'Suivant');
      expect(harness.methods, ['POST', 'PATCH']);
      expect(jsonDecode(harness.requests.last.body)['boat_type'], 'catamaran');
    });

    testWidgets('échec des préférences : message puis « Passer »', (
      tester,
    ) async {
      final harness = await _open(tester);
      harness.preferencesFailure = Exception('réseau');
      await _tap(tester, 'Je n’ai pas de bateau');
      await _tap(tester, 'Afficher mon nom d’utilisateur');

      await _tap(tester, 'Continuer');
      expect(
        find.textContaining('Vos choix n’ont pas pu être enregistrés'),
        findsOneWidget,
      );
      expect(find.text('Sur vos signalements'), findsOneWidget);

      await _tap(tester, 'Passer');
      expect(harness.preferences, [
        {'show_user_name': true},
      ]);
      expect(find.text('Alertes à proximité'), findsOneWidget);
    });

    testWidgets('n’envoie que les choix qui changent le profil', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        profile: _profile.copyWith(showUserName: true, showBoatInfo: true),
      );
      await _tap(tester, 'Je n’ai pas de bateau');
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await _tap(tester, 'Continuer');
      expect(harness.preferences, isEmpty);
      expect(find.text('Alertes à proximité'), findsOneWidget);
    });
  });

  group('alertes', () {
    testWidgets('active les alertes puis demande l’autorisation', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _skipToAlerts(tester);

      await tester.tap(find.text('Activer les alertes'));
      // Le chargement tourne jusqu'à ce que le parent change d'écran :
      // pumpAndSettle ne s'arrêterait jamais.
      await tester.pump();

      expect(harness.preferences, [
        {'notifications_enabled': true},
      ]);
      expect(harness.permissions.requestCalls, 1);
      expect(harness.done, 1);
    });

    testWidgets('« Plus tard » termine sans rien enregistrer ni demander', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _skipToAlerts(tester);

      await _tap(tester, 'Plus tard');

      expect(harness.preferences, isEmpty);
      expect(harness.permissions.requestCalls, 0);
      expect(harness.done, 1);
    });

    testWidgets('échec de l’enregistrement : message, la page reste', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _skipToAlerts(tester);
      harness.preferencesFailure = Exception('réseau');

      await _tap(tester, 'Activer les alertes');

      expect(
        find.text('Impossible d’activer les alertes. Réessayez.'),
        findsOneWidget,
      );
      expect(harness.permissions.requestCalls, 0);
      expect(harness.done, 0);
      expect(find.text('Activer les alertes'), findsOneWidget);
    });

    testWidgets('retour : revient à la visibilité, puis au bateau', (
      tester,
    ) async {
      final harness = await _open(tester);
      await _skipToAlerts(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sur vos signalements'), findsOneWidget);
      expect(find.text('ÉTAPE 4 SUR 5'), findsOneWidget);

      // Sans bateau, la visibilité revient au choix du type.
      await _back(tester);
      expect(find.text('Votre bateau'), findsOneWidget);
      expect(harness.done, 0);
    });
  });
}
