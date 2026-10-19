import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/presentation/alert_report_screen.dart';
import 'package:blueway/features/alerts/presentation/alerts_screen.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/auth/presentation/auth_gate.dart';
import 'package:blueway/features/auth/presentation/login_screen.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/presentation/account_deletion_screen.dart';
import 'package:blueway/features/profile/presentation/boat_screen.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/notifications/fake_notification_permission_service.dart';
import '../features/alerts/support/alert_fixtures.dart';
import '../features/profile/data/boat_service_test.dart' show boatJson;
import '../features/profile/support/account_deletion_fixture.dart'
    show TestPush, TestIds, TestLocation;

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
  User? currentUser;
  @override
  Stream<User?> get userChanges => changes.stream;
  void login(String uid) {
    currentUser = _User(uid);
    changes.add(currentUser);
  }

  @override
  Future<String> getIdToken() async => 'test-${currentUser!.uid}';
  @override
  Future<void> signOut() async {
    currentUser = null;
    changes.add(null);
  }
}

class _Tokens extends TestPush {
  // Un flux simple garde l'annulation dans la zone de temps du widget test.
  final refreshes = StreamController<String>.broadcast();
  @override
  Stream<String> get onTokenRefresh {
    StreamSubscription<String>? subscription;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () => subscription = refreshes.stream.listen(controller.add),
      onCancel: () async => unawaited(subscription?.cancel()),
    );
    return controller.stream;
  }
}

class _Session {
  final auth = _Auth();
  final source = FakeAlertPushSource();
  final tokens = _Tokens();
  final ids = TestIds();
  final requests = <http.Request>[];
  final events = <String>[];
  late final AlertPushController controller;
  late final ApiService api;
  late final MockClient client;
  late final DeviceRegistration registration;
  late final DevicePositionReporter reporter;
  Map<String, dynamic>? boat;
  bool suspended = false;
  Completer<http.Response>? pendingHistory;

  _Session() {
    SharedPreferences.setMockInitialValues({
      'installation_id': 'installation-old',
    });
    controller = AlertPushController(source: source, now: () => testNow);
    client = MockClient((request) async {
      requests.add(request);
      events.add('${request.method} ${request.url.path}');
      final path = request.url.path;
      if (path.endsWith('/devices/current')) return http.Response('', 204);
      if (path.endsWith('/boat')) {
        if (request.method == 'GET') {
          return boat == null
              ? http.Response('{"error":{"code":"boat_not_found"}}', 404)
              : http.Response(jsonEncode(boat), 200);
        }
        boat = {
          ...boatJson,
          ...jsonDecode(request.body) as Map<String, dynamic>,
        };
        return http.Response(jsonEncode(boat), 201);
      }
      if (path.endsWith('/alerts')) {
        if (pendingHistory != null) return pendingHistory!.future;
        final uid = auth.currentUser!.uid;
        return http.Response(
          jsonEncode(pageJson(items: [alertJson(id: 'alert-$uid')])),
          200,
        );
      }
      if (path.contains('/reports/')) return http.Response('', 404);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response(
        jsonEncode({
          'id': 'profile-${auth.currentUser!.uid}',
          'username': 'user-${auth.currentUser!.uid}',
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
    api = ApiService(client: client, baseUrl: 'https://nowave.test/');
    final devices = DeviceService(
      apiService: api,
      getIdToken: auth.getIdToken,
      installationIds: ids,
    );
    registration = DeviceRegistration(
      devices: devices,
      pushTokens: tokens,
      permissions: FakeNotificationPermissionService(),
      installationIds: ids,
    );
    reporter = DevicePositionReporter(
      devices: devices,
      registration: registration,
      location: TestLocation(),
    );
  }

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await reporter.stop();
      await registration.stop();
      await tokens.refreshes.close();
      await auth.changes.close();
      await source.close();
      client.close();
    });
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
          deviceRegistration: registration,
          devicePositionReporter: reporter,
          alertService: AlertService(
            apiService: api,
            getIdToken: auth.getIdToken,
          ),
          pushController: controller,
        ),
      ),
    );
    await tester.pump();
    auth.login('a');
    await tester.pumpAndSettle();
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mon profil'));
    await tester.pumpAndSettle();
  }

  Future<void> deleteAction(WidgetTester tester) async {
    if (!suspended) await openProfile(tester);
    await tester.ensureVisible(find.text('Supprimer mon compte'));
    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDeletionScreen), findsOneWidget);
  }
}

void main() {
  testWidgets(
    'NW128-I01 profil → bateau → historique → FCM sur la même session',
    (tester) async {
      final f = _Session();
      await f.mount(tester);
      await f.openProfile(tester);
      await tester.ensureVisible(find.text('Mon bateau'));
      await tester.tap(find.text('Mon bateau'));
      await tester.pumpAndSettle();
      expect(find.byType(BoatScreen), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Integration');
      await tester.enterText(find.byType(TextFormField).last, 'FR');
      await tester.tap(find.text('Créer le bateau'));
      await tester.pumpAndSettle();
      expect(f.boat!['name'], 'Integration');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alert-a')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      f.source.taps.add(pushMessage());
      f.source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.byType(AlertReportScreen), findsNothing);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(
        find.text('Ce signalement n’est plus disponible.'),
        findsOneWidget,
      );
      expect(
        f.requests.where((r) => r.url.path.contains('/reports/')),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final suspended in [false, true]) {
    testWidgets(
      'NW128-I02 suppression ${suspended ? 'suspendue' : 'active'} et nettoyage device',
      (tester) async {
        final f = _Session()..suspended = suspended;
        await f.mount(tester);
        await f.deleteAction(tester);
        f.source.taps.add(pushMessage());
        await tester.tap(find.text('Supprimer définitivement mon compte'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
          f.requests.where((r) => r.method == 'DELETE').map((r) => r.url.path),
          ['/api/v1/users/me'],
        );
        expect(f.tokens.deletions, 1);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('installation_id'), isNull);
        expect(prefs.getStringList('account_deletion'), isNull);
        expect(f.auth.currentUser, isNull);
        f.suspended = false;
        f.auth.login('b');
        await tester.pumpAndSettle();
        expect(find.byType(AlertReportScreen), findsNothing);
        expect(
          f.requests.where((r) => r.url.path.contains('/reports/')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'NW128-I03 confirmation suppression bloque immédiatement le push puis annulation reprend',
    (tester) async {
      final f = _Session();
      await f.mount(tester);
      await f.openProfile(tester);
      await tester.ensureVisible(find.text('Supprimer mon compte'));
      await tester.tap(find.text('Supprimer mon compte'));
      // Avant la frame suivante : le callback de l'ancien accueil est encore attaché.
      f.source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.byType(AlertReportScreen), findsNothing);
      expect(find.byType(AccountDeletionScreen), findsOneWidget);
      f.source.messages.add(pushMessage(id: 'foreground-during-deletion'));
      expect(f.controller.foreground, isNull);
      expect(
        f.requests.where((r) => r.url.path.contains('/reports/')),
        isEmpty,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertReportScreen), findsNothing);
      expect(find.byType(MapScreen), findsOneWidget);
      expect(
        find.text('Ce signalement n’est plus disponible.'),
        findsOneWidget,
      );
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'NW128-I04 changement de compte écarte historique et réponse tardive du précédent',
    (tester) async {
      final f = _Session();
      await f.mount(tester);
      f.pendingHistory = Completer<http.Response>();
      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pump();
      f.auth.login('b');
      await tester.pump();
      f.pendingHistory!.complete(
        http.Response(
          jsonEncode(pageJson(items: [alertJson(id: 'private-a')])),
          200,
        ),
      );
      f.pendingHistory = null;
      await tester.pumpAndSettle();
      expect(find.byType(AlertsScreen), findsNothing);
      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('private-a')), findsNothing);
      expect(find.byKey(const ValueKey('alert-b')), findsOneWidget);
      expect(f.requests.last.headers['authorization'], 'Bearer test-b');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'NW128-I05 logout nettoie le device puis reconnexion sans anciennes alertes',
    (tester) async {
      final f = _Session();
      await f.mount(tester);
      await f.openProfile(tester);
      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        f.requests.where((r) => r.method == 'DELETE').map((r) => r.url.path),
        ['/api/v1/devices/current'],
      );
      expect(f.tokens.deletions, 1);
      expect(
        (await SharedPreferences.getInstance()).getString('installation_id'),
        isNull,
      );
      f.auth.login('b');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes alertes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alert-b')), findsOneWidget);
      expect(f.requests.last.headers['authorization'], 'Bearer test-b');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
