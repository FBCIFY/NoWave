import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/device/installation_id_store.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/notifications/push_tokens.dart';
import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:blueway/features/profile/presentation/profile_gate.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/fake_notification_permission_service.dart';

class _Auth extends Fake implements AuthService {
  String? account = 'a';
  int signOutCalls = 0;
  bool failSignOut = false;

  @override
  Future<String> getIdToken() async {
    if (account == null) throw StateError('Session fermée');
    return 'token-$account';
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) throw StateError('Firebase indisponible');
    account = null;
  }
}

class _PushTokens extends Fake implements PushTokens {
  bool failDelete = false;
  final refreshes = StreamController<String>.broadcast();

  /// Le `cancel()` d'un flux broadcast renvoie un Future de la zone racine,
  /// que l'horloge simulée de `testWidgets` ne fait jamais aboutir : la
  /// déconnexion resterait bloquée. On passe par un flux simple.
  @override
  Stream<String> get onTokenRefresh {
    StreamSubscription<String>? source;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () => source = refreshes.stream.listen(controller.add),
      onCancel: () async => unawaited(source?.cancel()),
    );
    return controller.stream;
  }

  @override
  Future<String?> getToken() async => 'fcm-token';

  @override
  Future<void> deleteToken() async {
    if (failDelete) throw StateError('FCM indisponible');
  }
}

class _Location extends LocationService {
  @override
  Future<bool> canWatchPosition() async => false;
}

void main() {
  late _Auth auth;
  late _PushTokens pushTokens;
  late InstallationIdStore installationIds;
  late DeviceRegistration registration;
  late DevicePositionReporter reporter;
  late ApiService api;
  late List<http.Request> requests;
  late bool failDelete;
  Completer<void>? deleteResponse;

  void setUpServices() {
    SharedPreferences.setMockInitialValues({});
    var nextId = 0;
    installationIds = InstallationIdStore(
      newId: () => 'installation-${++nextId}',
    );
    auth = _Auth();
    pushTokens = _PushTokens();
    addTearDown(pushTokens.refreshes.close);
    requests = [];
    failDelete = false;
    deleteResponse = null;
    final client = MockClient((request) async {
      requests.add(request);
      // Le parcours de déconnexion reste disponible si le profil ne charge pas.
      if (request.method == 'GET') return http.Response('', 503);
      if (request.method == 'DELETE') {
        await deleteResponse?.future;
        if (failDelete) return http.Response('', 503);
        return http.Response('', 204);
      }
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    api = ApiService(client: client, baseUrl: 'https://nowave.test/');
    final devices = DeviceService(
      apiService: api,
      getIdToken: auth.getIdToken,
      installationIds: installationIds,
    );
    registration = DeviceRegistration(
      devices: devices,
      pushTokens: pushTokens,
      permissions: FakeNotificationPermissionService(),
      installationIds: installationIds,
    );
    reporter = DevicePositionReporter(
      devices: devices,
      registration: registration,
      location: _Location(),
    );
    addTearDown(registration.stop);
    addTearDown(reporter.stop);
  }

  Future<void> openGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileGate(
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('double échec : garde la session A, réessaie avec son token '
      'puis autorise l’enregistrement du compte B', (tester) async {
    setUpServices();
    await registration.start();
    failDelete = true;
    pushTokens.failDelete = true;
    await openGate(tester);

    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();
    expect(auth.account, 'a');
    expect(auth.signOutCalls, 0);
    expect(await installationIds.read(), 'installation-1');
    expect(find.textContaining('Votre session est conservée'), findsOneWidget);

    // Le bouton retour et le retour au premier plan ne contournent pas l'échec.
    await tester.binding.handlePopRoute();
    await registration.start();
    await registration.register();
    await reporter.start();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(requests.where((r) => r.method == 'PUT'), hasLength(1));

    failDelete = false;
    pushTokens.failDelete = false;
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Réessayer'),
      ),
    );
    await tester.pumpAndSettle();
    expect(auth.account, isNull);
    expect(auth.signOutCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    final deletions = requests.where((r) => r.method == 'DELETE').toList();
    expect(deletions, hasLength(2));
    expect(deletions.map((r) => r.headers['Authorization']), [
      'Bearer token-a',
      'Bearer token-a',
    ]);
    expect(deletions.map((r) => r.headers['X-Installation-ID']), [
      'installation-1',
      'installation-1',
    ]);

    auth.account = 'b';
    await registration.start();
    final newRegistration = requests.last;
    expect(newRegistration.headers['Authorization'], 'Bearer token-b');
    expect(
      jsonDecode(newRegistration.body)['installation_id'],
      'installation-2',
    );
  });

  testWidgets('hors ligne, Annuler garde le compte A et autorise de nouveau '
      'son enregistrement', (tester) async {
    setUpServices();
    await registration.start();
    failDelete = true;
    await openGate(tester);

    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(auth.account, 'a');
    expect(auth.signOutCalls, 0);
    expect(registration.isSigningOut, isFalse);
    await registration.start();
    final puts = requests.where((r) => r.method == 'PUT').toList();
    expect(puts, hasLength(2));
    expect(jsonDecode(puts.last.body)['installation_id'], 'installation-1');
    expect(puts.last.headers['Authorization'], 'Bearer token-a');
  });

  testWidgets('un DELETE en cours affiche l’attente et conserve la session '
      'et l’identifiant', (tester) async {
    setUpServices();
    await registration.start();
    deleteResponse = Completer<void>();
    await openGate(tester);
    await tester.tap(find.text('Déconnexion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Déconnexion en cours…'), findsOneWidget);
    expect(auth.signOutCalls, 0);
    expect(await installationIds.read(), 'installation-1');
    expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));

    deleteResponse!.complete();
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('si signOut Firebase échoue après le nettoyage, la reprise '
      'ne recrée pas d’appareil', (tester) async {
    setUpServices();
    await registration.start();
    auth.failSignOut = true;
    await openGate(tester);
    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();

    expect(auth.account, 'a');
    await registration.start();
    expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
    auth.failSignOut = false;
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Réessayer'),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.account, isNull);
    expect(auth.signOutCalls, 2);
    expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
  });
}
