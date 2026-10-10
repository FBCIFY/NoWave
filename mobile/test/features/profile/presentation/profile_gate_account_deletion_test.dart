import 'dart:convert';

import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/profile/presentation/account_deletion_screen.dart';
import 'package:blueway/features/profile/presentation/profile_gate.dart';
import 'package:blueway/features/profile/presentation/profile_setup_screen.dart';
import 'package:blueway/features/profile/presentation/suspended_account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/account_deletion_fixture.dart';

class _Reports extends Fake implements ManualReportService {}

class _Estimates extends Fake implements PositionEstimateService {}

class _Tiles extends Fake implements ReportTiles {}

class _Details extends Fake implements ReportDetailService {}

void main() {
  Future<void> openSuspendedGate(WidgetTester tester, AccountFixture f) async {
    f.respond = (request) async => request.method == 'GET'
        ? http.Response(
            jsonEncode({
              'id': 'profile-a',
              'username': 'Test suspendu',
              'role': 'user',
              'status': 'suspended',
              'show_user_name': false,
              'show_boat_info': false,
              'notifications_enabled': false,
              'created_at': '2026-10-01T00:00:00Z',
              'updated_at': '2026-10-01T00:00:00Z',
            }),
            200,
          )
        : http.Response('', 204);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileGate(
          authService: f.auth,
          profileService: f.profiles,
          reportService: _Reports(),
          positionEstimateService: _Estimates(),
          reportTiles: _Tiles(),
          reportDetailService: _Details(),
          deviceRegistration: f.registration,
          devicePositionReporter: f.reporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compte suspendu : action de suppression, confirmation et annulation sans envoi',
    (tester) async {
      final f = AccountFixture();
      addTearDown(f.dispose);
      await openSuspendedGate(tester, f);
      expect(find.byType(SuspendedAccountScreen), findsOneWidget);
      expect(find.text('Supprimer mon compte'), findsOneWidget);
      expect(find.text('Déconnexion'), findsOneWidget);
      await tester.tap(find.text('Supprimer mon compte'));
      await tester.pumpAndSettle();
      final screen = tester.widget<AccountDeletionScreen>(
        find.byType(AccountDeletionScreen),
      );
      // Le gate transmet les mêmes services à l'orchestrateur de production.
      expect(screen.deletion.profileService, same(f.profiles));
      expect(screen.deletion.authService, same(f.auth));
      expect(screen.deletion.registration, same(f.registration));
      expect(screen.deletion.reporter, same(f.reporter));
      expect(find.text('Supprimer définitivement mon compte'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(SuspendedAccountScreen), findsOneWidget);
      expect(find.byType(AccountDeletionScreen), findsNothing);
      expect(f.requests.map((r) => r.method), ['GET']);
      expect(f.auth.signOutCalls, 0);
      expect(await f.ids.read(), 'installation-old');
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'account_deletion',
        ),
        isNull,
      );
      // Rouvrir conserve exactement l'instance orchestrée par ProfileGate.
      await tester.tap(find.text('Supprimer mon compte'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountDeletionScreen>(find.byType(AccountDeletionScreen))
            .deletion,
        same(screen.deletion),
      );
    },
  );

  testWidgets(
    'compte suspendu : le parcours commun supprime puis nettoie sur 204',
    (tester) async {
      final f = AccountFixture();
      addTearDown(f.dispose);
      await openSuspendedGate(tester, f);
      await tester.tap(find.text('Supprimer mon compte'));
      await tester.pumpAndSettle();
      final deletion = tester
          .widget<AccountDeletionScreen>(find.byType(AccountDeletionScreen))
          .deletion;
      await tester.tap(find.text('Supprimer définitivement mon compte'));
      await tester.pumpAndSettle();
      expect(deletion.confirmed, isTrue);
      expect(f.requests.map((r) => r.method), ['GET', 'DELETE']);
      final request = f.requests.last;
      expect(request.url.path, '/api/v1/users/me');
      expect(request.headers['authorization'], 'Bearer test-token');
      expect(request.body, isEmpty);
      expect(f.auth.currentUser, isNull);
      expect(f.auth.signOutCalls, 1);
      expect(f.push.deletions, 1);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('installation_id'), isNull);
      expect(preferences.getStringList('account_deletion'), isNull);
    },
  );

  testWidgets(
    'journal restauré avant GET profil : pas de recréation et pas de reprise lifecycle',
    (tester) async {
      final f = AccountFixture();
      addTearDown(f.dispose);
      f.respond = (_) async => http.Response('', 503);
      await expectLater(f.deletion.run(), throwsA(anything));
      final events = ValueNotifier(0);
      addTearDown(events.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileGate(
            authService: f.auth,
            profileService: f.profiles,
            reportService: _Reports(),
            positionEstimateService: _Estimates(),
            reportTiles: _Tiles(),
            reportDetailService: _Details(),
            deviceRegistration: f.registration,
            devicePositionReporter: f.reporter,
            inactiveUserEvents: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      expect(find.byType(ProfileSetupScreen), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(f.requests, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      events.value++;
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      expect(f.requests, hasLength(1));
      f.respond = (_) async => http.Response('', 204);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(f.auth.currentUser, isNull);
      expect(f.requests.map((r) => r.method), ['DELETE', 'DELETE']);
    },
  );
}
