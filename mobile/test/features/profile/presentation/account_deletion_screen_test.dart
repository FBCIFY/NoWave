import 'dart:async';

import 'package:blueway/features/profile/presentation/account_deletion_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/account_deletion_fixture.dart';

void main() {
  late AccountFixture f;
  late bool cancelled;
  late bool done;
  setUp(() {
    cancelled = false;
    done = false;
  });
  tearDown(() => f.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(
          deletion: f.deletion,
          onCancel: () => cancelled = true,
          onDone: () => done = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('confirmation explicite et annulation sans requête', (
    tester,
  ) async {
    f = AccountFixture();
    await open(tester);
    expect(
      find.textContaining('Cette action est irréversible'),
      findsOneWidget,
    );
    expect(f.requests, isEmpty);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(f.requests, isEmpty);
    expect(f.auth.signOutCalls, 0);
  });

  testWidgets('confirmation 204 nettoie la session et termine', (tester) async {
    f = AccountFixture();
    await open(tester);
    await tester.tap(find.text('Supprimer définitivement mon compte'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(f.auth.currentUser, isNull);
    expect(f.requests, hasLength(1));
  });

  testWidgets(
    'timeout interdit le retour à un profil potentiellement supprimé',
    (tester) async {
      f = AccountFixture();
      final response = Completer<http.Response>();
      f.respond = (_) => response.future;
      await open(tester);
      await tester.tap(find.text('Supprimer définitivement mon compte'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      expect(f.auth.currentUser, isNotNull);
      expect(find.text('Annuler'), findsNothing);
      expect(
        find.textContaining('Certaines données peuvent déjà'),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      response.complete(http.Response('', 204));
      f.respond = (_) async => http.Response('', 204);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    },
  );
}
