import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/presentation/boat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../data/boat_service_test.dart' show boatJson;

void main() {
  late List<http.Request> requests;
  Map<String, Object?>? boat;
  int? failure;
  Completer<http.Response>? pending;

  Future<void> open(WidgetTester tester) async {
    requests = [];
    final client = MockClient((r) async {
      requests.add(r);
      if (failure != null) return http.Response('{}', failure!);
      if (r.method == 'GET') {
        return boat == null
            ? http.Response('{"error":{"code":"boat_not_found"}}', 404)
            : http.Response(jsonEncode(boat), 200);
      }
      if (pending != null) return pending!.future;
      if (r.method == 'DELETE') {
        boat = null;
        return http.Response('', 204);
      }
      boat = {...boatJson, ...jsonDecode(r.body) as Map<String, dynamic>};
      return http.Response(jsonEncode(boat), r.method == 'POST' ? 201 : 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BoatScreen(
          profileService: ProfileService(
            apiService: ApiService(
              client: client,
              baseUrl: 'https://nowave.test/',
            ),
            getIdToken: () async => 'test-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    boat = null;
    failure = null;
    pending = null;
  });

  testWidgets('absent, création, modification et suppression confirmée', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Aucun bateau enregistré'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'aurore');
    await tester.enterText(find.byType(TextFormField).last, 'fr');
    await tester.tap(find.text('Créer le bateau'));
    await tester.pumpAndSettle();
    expect(boat!['name'], 'Aurore');
    expect(find.text('Enregistrer'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Aurore II');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(boat!['name'], 'Aurore II');
    await tester.tap(find.text('Supprimer le bateau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('Supprimer le bateau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(boat, isNull);
    expect(find.text('Aucun bateau enregistré'), findsOneWidget);
    expect(requests.map((r) => r.method), ['GET', 'POST', 'PATCH', 'DELETE']);
  });

  testWidgets('erreur de lecture puis retry sans création accidentelle', (
    tester,
  ) async {
    failure = 503;
    await open(tester);
    expect(find.text('Créer le bateau'), findsNothing);
    expect(find.textContaining('Impossible de charger'), findsOneWidget);
    failure = null;
    await tester.tap(find.text('Recharger le bateau'));
    await tester.pumpAndSettle();
    expect(find.text('Créer le bateau'), findsOneWidget);
  });

  testWidgets(
    'conflit 409 garde la saisie et permet de relire le bateau existant',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Saisie conservée',
      );
      failure = 409;
      await tester.tap(find.text('Créer le bateau'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Un bateau existe déjà'), findsOneWidget);
      expect(find.text('Saisie conservée'), findsOneWidget);
      failure = null;
      boat = boatJson;
      await tester.tap(find.text('Recharger le bateau'));
      await tester.pumpAndSettle();
      expect(find.text('Aurore'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    },
  );

  testWidgets('validation pavillon avant envoi', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).last, 'F1');
    await tester.tap(find.text('Créer le bateau'));
    await tester.pumpAndSettle();
    expect(
      find.text('Saisissez un code pays de deux lettres.'),
      findsOneWidget,
    );
    expect(requests, hasLength(1));
  });

  testWidgets(
    'timeout POST, pas de doublon automatique, récupération par GET',
    (tester) async {
      await open(tester);
      pending = Completer<http.Response>();
      await tester.tap(find.text('Créer le bateau'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Enregistrement non confirmé'),
        findsOneWidget,
      );
      // Le serveur avait enregistré le bateau, mais sa réponse s'est perdue.
      boat = boatJson;
      pending!.complete(http.Response(jsonEncode(boat), 201));
      pending = null;
      await tester.tap(find.text('Recharger le bateau'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  testWidgets('suppression en erreur conserve le bateau', (tester) async {
    boat = boatJson;
    await open(tester);
    failure = 503;
    await tester.tap(find.text('Supprimer le bateau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Suppression non confirmée'), findsOneWidget);
    expect(find.text('Aurore'), findsOneWidget);
  });
}
