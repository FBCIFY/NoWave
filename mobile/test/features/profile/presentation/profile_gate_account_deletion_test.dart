import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/profile/presentation/account_deletion_screen.dart';
import 'package:blueway/features/profile/presentation/profile_gate.dart';
import 'package:blueway/features/profile/presentation/profile_setup_screen.dart';
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
