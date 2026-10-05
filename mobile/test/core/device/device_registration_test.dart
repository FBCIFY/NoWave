import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/device/device_position.dart';
import 'package:blueway/core/device/device_registration.dart';
import 'package:blueway/core/device/device_service.dart';
import 'package:blueway/core/device/installation_id_store.dart';
import 'package:blueway/core/notifications/notification_permission.dart';
import 'package:blueway/core/notifications/push_tokens.dart';

import '../notifications/fake_notification_permission_service.dart';

/// Faux backend : note chaque enregistrement et répond avec les erreurs
/// prévues, une par appel.
class _FakeDeviceService implements DeviceService {
  final InstallationIdStore installationIds;
  final List<Object> errors;
  final List<({String installationId, String? fcmToken})> registrations = [];

  /// Identifiants désactivés, et ordre des appels (`register` / `deactivate`).
  final List<String> deactivations = [];
  final List<String> calls = [];

  /// Si défini, [register] ne répond qu'une fois ce futur terminé.
  Future<void>? response;

  _FakeDeviceService(this.installationIds, [List<Object>? errors])
    : errors = errors ?? [];

  @override
  Future<void> register({String? fcmToken}) async {
    final installationId = await installationIds.read();
    registrations.add((installationId: installationId, fcmToken: fcmToken));
    calls.add('register');
    if (response case final response?) await response;
    if (errors.isNotEmpty) throw errors.removeAt(0);
  }

  @override
  Future<void> sendPosition(DevicePosition position) =>
      throw UnimplementedError();

  @override
  Future<void> deactivate() async {
    deactivations.add(await installationIds.read());
    calls.add('deactivate');
    if (errors.isNotEmpty) throw errors.removeAt(0);
  }
}

/// Faux Firebase : chaque [deleteToken] fait passer au token suivant.
class _FakePushTokens implements PushTokens {
  int getTokenCalls = 0;

  final StreamController<String> refreshes =
      StreamController<String>.broadcast();
  int generation = 1;
  int deleteCalls = 0;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    return 'fcm-$generation';
  }

  @override
  Future<void> deleteToken() async {
    deleteCalls++;
    generation++;
  }
}

ApiException _conflict() {
  return const ApiException(
    statusCode: 409,
    body: '{"error":{"code":"device_conflict","message":"conflict"}}',
  );
}

void main() {
  late int createdIds;
  late InstallationIdStore installationIds;
  late _FakePushTokens pushTokens;
  late FakeNotificationPermissionService permissions;

  setUp(() {
    createdIds = 0;
    SharedPreferences.setMockInitialValues({});
    installationIds = InstallationIdStore(
      newId: () => 'installation-${++createdIds}',
    );
    pushTokens = _FakePushTokens();
    permissions = FakeNotificationPermissionService(
      NotificationPermission.granted,
    );
    addTearDown(pushTokens.refreshes.close);
  });

  DeviceRegistration createRegistration(_FakeDeviceService devices) {
    return DeviceRegistration(
      devices: devices,
      pushTokens: pushTokens,
      permissions: permissions,
      installationIds: installationIds,
    );
  }

  test('start enregistre le téléphone avec le token actuel', () async {
    final devices = _FakeDeviceService(installationIds);

    await createRegistration(devices).start();

    expect(devices.registrations, [
      (installationId: 'installation-1', fcmToken: 'fcm-1'),
    ]);
  });

  test('réenregistre à chaque nouveau token, jusqu’à stop', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.start();

    pushTokens.refreshes.add('fcm-renouvelé');
    await pumpEventQueue();
    await registration.stop();
    pushTokens.refreshes.add('fcm-ignoré');
    await pumpEventQueue();

    expect(devices.registrations.map((r) => r.fcmToken), [
      'fcm-1',
      'fcm-renouvelé',
    ]);
  });

  test('les enregistrements simultanés partent dans l’ordre', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);

    await Future.wait([
      registration.register(refreshedToken: 'premier'),
      registration.register(refreshedToken: 'second'),
    ]);

    expect(devices.registrations.map((r) => r.fcmToken), ['premier', 'second']);
  });

  test('409 : réessaie avec un nouveau token FCM', () async {
    final devices = _FakeDeviceService(installationIds, [_conflict()]);

    await createRegistration(devices).register();

    expect(pushTokens.deleteCalls, 1);
    expect(devices.registrations, [
      (installationId: 'installation-1', fcmToken: 'fcm-1'),
      (installationId: 'installation-1', fcmToken: 'fcm-2'),
    ]);
  });

  test('409 persistant : réessaie avec un nouvel identifiant', () async {
    final devices = _FakeDeviceService(installationIds, [
      _conflict(),
      _conflict(),
    ]);

    await createRegistration(devices).register();

    expect(devices.registrations.last, (
      installationId: 'installation-2',
      fcmToken: 'fcm-2',
    ));
    expect(await installationIds.read(), 'installation-2');
  });

  test('une erreur réseau ne lève rien et ne bloque pas la suite', () async {
    final devices = _FakeDeviceService(installationIds, [
      TimeoutException('pas de réseau'),
    ]);
    final registration = createRegistration(devices);

    await registration.register();
    await registration.register();

    expect(devices.registrations, hasLength(2));
    expect(pushTokens.deleteCalls, 0);
  });

  test(
    'une autre erreur du backend ne change ni token ni identifiant',
    () async {
      final devices = _FakeDeviceService(installationIds, [
        const ApiException(statusCode: 404, body: ''),
      ]);

      await createRegistration(devices).register();

      expect(pushTokens.deleteCalls, 0);
      expect(await installationIds.read(), 'installation-1');
    },
  );

  test('sans autorisation, envoie null pour effacer l’ancien token', () async {
    permissions.status = NotificationPermission.denied;
    final devices = _FakeDeviceService(installationIds);

    await createRegistration(devices).register();

    expect(devices.registrations, [
      (installationId: 'installation-1', fcmToken: null),
    ]);
    expect(pushTokens.getTokenCalls, 0);
  });

  test('sans autorisation, ignore aussi un token renouvelé', () async {
    permissions.status = NotificationPermission.notDetermined;
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.start();

    pushTokens.refreshes.add('fcm-renouvelé');
    await pumpEventQueue();
    await registration.stop();

    expect(devices.registrations.map((r) => r.fcmToken), [null, null]);
  });

  test('sans autorisation, un 409 change directement d’identifiant', () async {
    permissions.status = NotificationPermission.denied;
    final devices = _FakeDeviceService(installationIds, [_conflict()]);

    await createRegistration(devices).register();

    expect(pushTokens.deleteCalls, 0);
    expect(devices.registrations, [
      (installationId: 'installation-1', fcmToken: null),
      (installationId: 'installation-2', fcmToken: null),
    ]);
  });

  test(
    'unregister désactive le téléphone, son token et son identifiant',
    () async {
      final devices = _FakeDeviceService(installationIds);
      final registration = createRegistration(devices);
      await registration.start();

      await registration.unregister();

      expect(devices.deactivations, ['installation-1']);
      expect(pushTokens.deleteCalls, 1);
      expect(await installationIds.read(), 'installation-2');
    },
  );

  test('unregister continue même si le DELETE échoue (hors ligne)', () async {
    final devices = _FakeDeviceService(installationIds, [
      TimeoutException('pas de réseau'),
    ]);

    await createRegistration(devices).unregister();

    expect(devices.deactivations, ['installation-1']);
    expect(pushTokens.deleteCalls, 1);
    expect(await installationIds.read(), 'installation-2');
  });

  test('unregister attend la fin de l’enregistrement en cours', () async {
    final response = Completer<void>();
    final devices = _FakeDeviceService(installationIds)
      ..response = response.future;
    final registration = createRegistration(devices);

    final registering = registration.register();
    await pumpEventQueue();
    final unregistering = registration.unregister();
    await pumpEventQueue();
    expect(devices.calls, ['register']);

    response.complete();
    await Future.wait([registering, unregistering]);

    expect(devices.calls, ['register', 'deactivate']);
  });

  test('unregister annule un enregistrement pas encore parti', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);

    await Future.wait([registration.register(), registration.unregister()]);

    expect(devices.calls, ['deactivate']);
  });

  test('après unregister, plus rien ne part jusqu’au prochain start', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.start();
    await registration.unregister();

    pushTokens.refreshes.add('fcm-ignoré');
    await pumpEventQueue();
    await registration.register();
    expect(devices.registrations, hasLength(1));

    await registration.start();

    expect(devices.registrations.last, (
      installationId: 'installation-2',
      fcmToken: 'fcm-2',
    ));
  });
}
