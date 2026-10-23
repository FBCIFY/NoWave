import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/domain/user_profile.dart';
import 'package:blueway/features/profile/presentation/personal_information_screen.dart';
import 'package:blueway/features/profile/presentation/profile_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _json = <String, Object?>{
  'id': 'profile-test',
  'username': 'Vadim',
  'date_of_birth': '1999-03-14',
  'nationality': 'FR',
  'role': 'user',
  'status': 'active',
  'show_user_name': false,
  'show_boat_info': false,
  'notifications_enabled': false,
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};

void main() {
  late List<http.Request> requests;
  late bool fail;
  UserProfile? result;

  Future<void> open(WidgetTester tester) async {
    requests = [];
    fail = false;
    result = null;
    final client = MockClient((request) async {
      requests.add(request);
      if (fail) return http.Response('{}', 503);
      return http.Response(
        jsonEncode({
          ..._json,
          ...jsonDecode(request.body) as Map<String, dynamic>,
        }),
        200,
      );
    });
    addTearDown(client.close);
    final service = ProfileService(
      apiService: ApiService(client: client, baseUrl: 'https://nowave.test/'),
      getIdToken: () async => 'test-token',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<UserProfile>(
                  profilePanelRoute(
                    (_) => PersonalInformationScreen(
                      profile: UserProfile.fromJson(_json),
                      service: service,
                    ),
                  ),
                );
              },
              child: const Text('Ouvrir le profil'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir le profil'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseBelgium(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nationalityField')));
    await tester.pumpAndSettle();
    final option = find.descendant(
      of: find.byKey(const Key('nationalityOptions')),
      matching: find.text('Belgique'),
    );
    await tester.scrollUntilVisible(
      option,
      150,
      scrollable: find.descendant(
        of: find.byKey(const Key('nationalityOptions')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('nationalityOptions')),
        matching: find.text('Belgique'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'aucune sauvegarde sans changement et retour aux valeurs d’origine',
    (tester) async {
      await open(tester);
      expect(find.text('Enregistrer'), findsNothing);
      expect(requests, isEmpty);
      await chooseBelgium(tester);
      expect(find.text('Enregistrer'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nationalityField')));
      await tester.pumpAndSettle();
      final option = find.descendant(
        of: find.byKey(const Key('nationalityOptions')),
        matching: find.text('France'),
      );
      await tester.scrollUntilVisible(
        option,
        150,
        scrollable: find.descendant(
          of: find.byKey(const Key('nationalityOptions')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('nationalityOptions')),
          matching: find.text('France'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer'), findsNothing);
      expect(requests, isEmpty);
    },
  );

  testWidgets('choisir la date initiale ne crée pas de modification', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('birthdayField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('la liste reste sous le champ et dans un petit écran', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('nationalityField')));
    await tester.tap(find.byKey(const Key('nationalityField')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    final field = tester.getRect(find.byKey(const Key('nationalityField')));
    final menu = tester.getRect(find.byKey(const Key('nationalityOptions')));
    expect(menu.top, greaterThan(field.bottom));
    expect(menu.bottom, lessThanOrEqualTo(568));
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'enregistre les informations personnelles sans toucher aux préférences',
    (tester) async {
      await open(tester);
      expect(find.text('14/03/1999'), findsOneWidget);
      await chooseBelgium(tester);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(requests.single.method, 'PATCH');
      expect(jsonDecode(requests.single.body), {
        'date_of_birth': '1999-03-14',
        'nationality': 'BE',
      });
      expect(result!.nationality, 'BE');
      expect(find.text('Ouvrir le profil'), findsOneWidget);
    },
  );

  testWidgets('conserve la saisie après une erreur et permet de réessayer', (
    tester,
  ) async {
    await open(tester);
    await chooseBelgium(tester);
    fail = true;
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(
      find.text('Impossible d’enregistrer. Vos saisies sont conservées.'),
      findsOneWidget,
    );
    expect(find.text('Belgique'), findsOneWidget);
    expect(result, isNull);
    fail = false;
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result!.nationality, 'BE');
  });

  testWidgets('le retour annule les saisies sans envoyer de requête', (
    tester,
  ) async {
    await open(tester);
    await chooseBelgium(tester);
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(result, isNull);
  });

  testWidgets('efface explicitement les deux informations facultatives', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Effacer la date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nationalityField')));
    await tester.pumpAndSettle();
    final item = find.descendant(
      of: find.byKey(const Key('nationalityOptions')),
      matching: find.text('Non renseignée'),
    );
    await tester.tap(item);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(jsonDecode(requests.single.body), {
      'date_of_birth': null,
      'nationality': null,
    });
    expect(result!.dateOfBirth, isNull);
    expect(result!.nationality, isNull);
  });

  testWidgets('le calendrier en français modifie la date enregistrée', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('birthdayField')));
    await tester.pumpAndSettle();
    expect(find.text('Annuler'), findsOneWidget);
    await tester.tap(find.text('15').first);
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();
    expect(find.text('15/03/1999'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result!.dateOfBirth, DateTime(1999, 3, 15));
  });
}
