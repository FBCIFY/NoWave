import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/presentation/alert_report_screen.dart';
import 'package:blueway/features/alerts/presentation/alerts_screen.dart';
import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/auth/presentation/auth_gate.dart';
import 'package:blueway/features/auth/presentation/login_screen.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/presentation/suspended_account_screen.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';

import '../support/alert_fixtures.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  bool get emailVerified => true;
}

class _Auth extends Fake implements AuthService {
  final changes = StreamController<User?>.broadcast(sync: true);
  @override
  Stream<User?> get userChanges => changes.stream;
  @override
  Future<String> getIdToken() async => 'test-token';
}

class _Registration extends Fake implements DeviceRegistration {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> register({String? refreshedToken}) async {}
}

class _Reporter extends Fake implements DevicePositionReporter {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  Future<({FakeAlertPushSource source, _Auth auth, List<String> calls})> mount(
    WidgetTester tester, {
    bool initial = false,
    bool suspended = false,
    bool reportAvailable = false,
  }) async {
    SharedPreferences.setMockInitialValues({});

    final auth = _Auth();
    final source = FakeAlertPushSource();
    if (initial) source.initial = pushMessage();
    final controller = AlertPushController(source: source, now: () => testNow);
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path.endsWith('/alerts')) {
        return http.Response(jsonEncode(pageJson()), 200);
      }
      if (request.url.path.contains('/reports/')) {
        if (!reportAvailable) return http.Response('', 404);
        return http.Response(
          jsonEncode({
            'id': 'report-a',
            'category': 'pollution',
            'description': 'Position actualisée',
            'positioning_mode': 'manual',
            'final_position': {
              'type': 'Point',
              'coordinates': [6.0, 44.0],
            },
            'status': 'active',
            'observed_at': testNow
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'author': null,
            'boat': null,
            'photo': null,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'profile-a',
          'username': 'test',
          'role': 'user',
          'status': suspended ? 'suspended' : 'active',
          'show_user_name': false,
          'show_boat_info': false,
          'notifications_enabled': false,
          'created_at': '2026-10-10T00:00:00Z',
          'updated_at': '2026-10-10T00:00:00Z',
        }),
        200,
      );
    });
    addTearDown(() async {
      client.close();
      await auth.changes.close();
      await source.close();
    });
    final api = ApiService(client: client, baseUrl: 'https://nowave.test/');
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          authService: auth,
          profileService: ProfileService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          reportService: ManualReportService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          positionEstimateService: PositionEstimateService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          reportTiles: ReportTiles(getIdToken: auth.getIdToken),
          reportDetailService: ReportDetailService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          deviceRegistration: _Registration(),
          devicePositionReporter: _Reporter(),
          alertService: AlertService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          pushController: controller,
        ),
      ),
    );
    await tester.pump();
    return (source: source, auth: auth, calls: calls);
  }

  testWidgets(
    'terminated simulé avant connexion, puis profil prêt, doublon et logout',
    (tester) async {
      final f = await mount(tester, initial: true);
      f.auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(f.calls, isEmpty);
      f.auth.changes.add(_User('user-a'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertReportScreen), findsOneWidget);
      expect(find.textContaining('n’est plus disponible'), findsOneWidget);
      expect(f.calls, ['/api/v1/users/me', '/api/v1/reports/report-a']);
      f.source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(f.calls, hasLength(2));
      f.auth.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(AlertReportScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'deux notifications distinctes empilent immédiatement leurs fiches',
    (tester) async {
      final f = await mount(tester, reportAvailable: true);

      f.auth.changes.add(_User('user-a'));
      await tester.pumpAndSettle();

      f.source.taps.add(pushMessage());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AlertReportScreen>(find.byType(AlertReportScreen))
            .reportId,
        'report-a',
      );

      f.source.taps.add(pushMessage(id: 'alert-b', reportId: 'report-b'));
      await tester.pumpAndSettle();

      final allScreens = tester
          .widgetList<AlertReportScreen>(
            find.byType(AlertReportScreen, skipOffstage: false),
          )
          .toList();

      expect(allScreens, hasLength(2));
      expect(
        tester
            .widget<AlertReportScreen>(find.byType(AlertReportScreen))
            .reportId,
        'report-b',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AlertReportScreen>(find.byType(AlertReportScreen))
            .reportId,
        'report-a',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('compte suspendu ne reçoit pas de navigation depuis FCM', (
    tester,
  ) async {
    final f = await mount(tester, initial: true, suspended: true);
    f.auth.changes.add(_User('user-a'));
    await tester.pumpAndSettle();
    f.source.taps.add(pushMessage());
    await tester.pumpAndSettle();
    expect(find.byType(SuspendedAccountScreen), findsOneWidget);
    expect(find.byType(AlertReportScreen), findsNothing);
    expect(f.calls, ['/api/v1/users/me']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('accueil ouvre l’historique puis la fiche existante', (
    tester,
  ) async {
    final f = await mount(tester);
    f.auth.changes.add(_User('user-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mes alertes'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertsScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert-a')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertReportScreen), findsOneWidget);
    expect(f.calls, [
      '/api/v1/users/me',
      '/api/v1/users/me/alerts',
      '/api/v1/reports/report-a',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Voir sur la carte reste bloqué pendant un signalement en cours',
    (tester) async {
      final f = await mount(tester, reportAvailable: true);

      f.auth.changes.add(_User('user-a'));
      await tester.pumpAndSettle();

      final map = tester.widget<MapScreen>(find.byType(MapScreen));
      final focusController = map.focusController!;

      focusController.setBlocked(true);

      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('alert-a')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertReportScreen), findsOneWidget);

      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertReportScreen), findsOneWidget);
      expect(focusController.report, isNull);
      expect(
        find.text(
          'Terminez ou annulez votre signalement avant de centrer la carte.',
        ),
        findsOneWidget,
      );

      focusController.setBlocked(false);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Voir sur la carte revient à la MapScreen principale et la cible',
    (tester) async {
      final f = await mount(tester, reportAvailable: true);

      f.auth.changes.add(_User('user-a'));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertsScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('alert-a')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertReportScreen), findsOneWidget);

      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertsScreen), findsNothing);
      expect(find.byType(AlertReportScreen), findsNothing);
      expect(find.byType(MapScreen), findsOneWidget);

      final map = tester.widget<MapScreen>(find.byType(MapScreen));
      final selected = map.focusController?.report;

      expect(selected, isNotNull);
      expect(selected!.id, 'report-a');
      expect(selected.longitude, 6);
      expect(selected.latitude, 44);

      final viewport =
          tester.widget<MapWidget>(find.byType(MapWidget)).viewport
              as CameraViewportState;

      expect(viewport.center!.coordinates.lng, 6);
      expect(viewport.center!.coordinates.lat, 44);
      expect(viewport.zoom, 14);

      expect(
        f.calls.where((path) => path == '/api/v1/reports/report-a').length,
        2,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
