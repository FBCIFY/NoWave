import 'dart:async';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/device/device_position_reporter.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/device/installation_id_store.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/notifications/push_tokens.dart';
import 'package:blueway/features/auth/data/auth_service.dart';
import 'package:blueway/features/profile/data/account_deletion.dart';
import 'package:blueway/features/profile/data/profile_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/fake_notification_permission_service.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid);
  @override
  final String uid;
}

class TestAuth extends Fake implements AuthService {
  @override
  User? currentUser = TestUser('account-a');
  bool failSignOut = false;
  int signOutCalls = 0;
  @override
  Future<String> getIdToken() async => 'test-token';
  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) throw StateError('Firebase indisponible');
    currentUser = null;
  }
}

class TestPush extends Fake implements PushTokens {
  int deletions = 0;
  bool fail = false;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Future<String?> getToken() async => 'test-fcm';
  @override
  Future<void> deleteToken() async {
    deletions++;
    if (fail) throw StateError('FCM indisponible');
  }
}

class TestLocation extends LocationService {
  @override
  Future<bool> canWatchPosition() async => false;
}

class TestIds extends InstallationIdStore {
  TestIds() : super(newId: () => 'installation-next');
  bool failReset = false;
  @override
  Future<void> reset() async {
    if (failReset) throw StateError('Stockage indisponible');
    await super.reset();
  }
}

/// Double HTTP uniquement : aucune requête ne sort vers Firebase ou l'API.
class AccountFixture {
  final auth = TestAuth();
  final push = TestPush();
  final ids = TestIds();
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  Future<http.Response> Function(http.Request)? respondDevice;
  late final MockClient client;
  late final ProfileService profiles;
  late final DeviceRegistration registration;
  late final DevicePositionReporter reporter;
  late final AccountDeletion deletion;

  AccountFixture() {
    SharedPreferences.setMockInitialValues({
      'installation_id': 'installation-old',
    });
    client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/api/v1/users/me') {
        return respond?.call(request) ?? http.Response('', 204);
      }
      return respondDevice?.call(request) ?? http.Response('{}', 200);
    });
    final api = ApiService(client: client, baseUrl: 'https://nowave.test/');
    profiles = ProfileService(apiService: api, getIdToken: auth.getIdToken);
    final devices = DeviceService(
      apiService: api,
      getIdToken: auth.getIdToken,
      installationIds: ids,
    );
    registration = DeviceRegistration(
      devices: devices,
      pushTokens: push,
      permissions: FakeNotificationPermissionService(),
      installationIds: ids,
    );
    reporter = DevicePositionReporter(
      devices: devices,
      registration: registration,
      location: TestLocation(),
    );
    deletion = newDeletion();
  }

  AccountDeletion newDeletion() => AccountDeletion(
    profileService: profiles,
    authService: auth,
    registration: registration,
    reporter: reporter,
  );

  Future<void> dispose() async {
    await reporter.stop();
    await registration.stop();
    client.close();
  }
}
