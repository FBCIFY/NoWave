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
  Future<void>? deactivationResponse;

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
    if (deactivationResponse case final response?) await response;
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
  Object? deleteError;
  Future<void>? tokenResponse;

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    await tokenResponse;
    return 'fcm-$generation';
  }

  @override
  Future<void> deleteToken() async {
    deleteCalls++;
    if (deleteError case final error?) throw error;
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

  test('unregister garde l’identifiant si le DELETE échoue, même si '
      'l’invalidation FCM réussit', () async {
    final devices = _FakeDeviceService(installationIds, [
      TimeoutException('pas de réseau'),
    ]);

    await expectLater(
      createRegistration(devices).unregister(),
      throwsA(isA<TimeoutException>()),
    );

    expect(devices.deactivations, ['installation-1']);
    expect(pushTokens.deleteCalls, 1);
    expect(await installationIds.read(), 'installation-1');
  });

  test('double échec : conserve l’ancien identifiant après redémarrage et '
      'réessaie le nettoyage sans bloquer la file', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.start();
    devices.errors.add(TimeoutException('pas de réseau'));
    pushTokens.deleteError = StateError('FCM indisponible');

    await expectLater(
      registration.unregister(),
      throwsA(isA<TimeoutException>()),
    );
    expect(await installationIds.read(), 'installation-1');
    expect(await InstallationIdStore().read(), 'installation-1');
    expect(registration.isSigningOut, isTrue);
    expect(registration.completeSignOut, throwsStateError);
    await registration.start();
    await registration.register();
    pushTokens.refreshes.add('token-pendant-déconnexion');
    await pumpEventQueue();
    expect(devices.registrations, hasLength(1));

    pushTokens.deleteError = null;
    await registration.unregister();
    expect(devices.deactivations, ['installation-1', 'installation-1']);
    expect(await installationIds.read(), 'installation-2');
    // Même nettoyé, il ne redémarre pas avant la fermeture de la session.
    await registration.start();
    expect(devices.registrations, hasLength(1));
    registration.completeSignOut();
    await registration.start();
    expect(devices.registrations.last.installationId, 'installation-2');
  });

  test(
    'annuler après un échec reprend l’enregistrement du même téléphone',
    () async {
      final devices = _FakeDeviceService(installationIds);
      final registration = createRegistration(devices);
      await registration.start();
      devices.errors.add(TimeoutException('pas de réseau'));

      await expectLater(
        registration.unregister(),
        throwsA(isA<TimeoutException>()),
      );
      registration.cancelSignOut();
      expect(registration.isSigningOut, isFalse);
      await registration.start();
      pushTokens.refreshes.add('token-renouvelé');
      await pumpEventQueue();

      expect(devices.registrations.map((r) => r.installationId), [
        'installation-1',
        'installation-1',
        'installation-1',
      ]);
      expect(devices.registrations.last.fcmToken, 'token-renouvelé');
    },
  );

  test('annuler est refusé une fois la session fermée', () async {
    final registration = createRegistration(
      _FakeDeviceService(installationIds),
    );
    await registration.unregister();
    registration.completeSignOut();

    expect(registration.cancelSignOut, throwsStateError);
  });

  test('se déconnecte d’une session qui n’a pas atteint l’accueil', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.unregister();
    registration.completeSignOut();

    final newId = await installationIds.read();

    // Compte suivant sans profil ou suspendu : start() n'est jamais appelé.
    await registration.unregister();
    registration.completeSignOut();

    expect(devices.deactivations, hasLength(1));
    expect(pushTokens.deleteCalls, 1);
    expect(await installationIds.read(), newId);

    // Le compte d'après arrive sur l'accueil : le téléphone s'enregistre.
    await registration.start();
    expect(devices.registrations.single.installationId, newId);
  });

  test('un échec Firebase après le nettoyage ne déclenche pas un DELETE '
      'sur un nouvel identifiant au prochain essai', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    await registration.start();
    await registration.unregister();
    await registration.unregister();

    expect(devices.deactivations, ['installation-1']);
    expect(pushTokens.deleteCalls, 1);
    expect(createdIds, 1);
    expect(registration.isSigningOut, isTrue);
  });

  test('si le backend confirme le nettoyage, un échec FCM ne bloque pas '
      'la déconnexion', () async {
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    pushTokens.deleteError = StateError('FCM indisponible');

    await registration.unregister();
    registration.completeSignOut();

    expect(devices.deactivations, ['installation-1']);
    expect(await installationIds.read(), 'installation-2');
  });

  for (final code in ['device_not_found', 'user_not_found']) {
    test('404 $code confirme qu’il ne reste rien à nettoyer', () async {
      final devices = _FakeDeviceService(installationIds, [
        ApiException(statusCode: 404, body: '{"error":{"code":"$code"}}'),
      ]);
      final registration = createRegistration(devices);

      await registration.unregister();
      registration.completeSignOut();

      expect(await installationIds.read(), 'installation-2');
    });
  }

  for (final error in [
    const ApiException(statusCode: 404, body: '<html>Not Found</html>'),
    const ApiException(statusCode: 401, body: ''),
    const ApiException(statusCode: 403, body: ''),
    const ApiException(statusCode: 503, body: ''),
  ]) {
    test('${error.statusCode} non confirmé garde l’identifiant et bloque '
        'le changement de compte', () async {
      final devices = _FakeDeviceService(installationIds, [error]);
      final registration = createRegistration(devices);

      await expectLater(registration.unregister(), throwsA(same(error)));

      expect(await installationIds.read(), 'installation-1');
      expect(registration.completeSignOut, throwsStateError);
    });
  }

  test(
    'une réponse DELETE perdue se réessaie avec l’ancien identifiant',
    () async {
      final response = Completer<void>();
      final devices = _FakeDeviceService(installationIds)
        ..deactivationResponse = response.future;
      final registration = createRegistration(devices);
      await registration.start();
      final unregistering = registration.unregister();
      final failed = expectLater(
        unregistering,
        throwsA(isA<TimeoutException>()),
      );
      await pumpEventQueue();
      await registration.start();
      await pumpEventQueue();
      expect(await installationIds.read(), 'installation-1');
      expect(devices.registrations, hasLength(1));
      response.completeError(TimeoutException('réponse perdue'));
      await failed;

      devices.deactivationResponse = null;
      await registration.unregister();
      expect(devices.deactivations, ['installation-1', 'installation-1']);
    },
  );

  test('un token obtenu tardivement ne réenregistre pas après le début '
      'de la déconnexion', () async {
    final response = Completer<void>();
    pushTokens.tokenResponse = response.future;
    final devices = _FakeDeviceService(installationIds);
    final registration = createRegistration(devices);
    final registering = registration.start();
    await pumpEventQueue();
    final unregistering = registration.unregister();
    response.complete();
    await Future.wait([registering, unregistering]);

    expect(devices.calls, ['deactivate']);
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

  test(
    'après unregister, plus rien ne part jusqu’à la session suivante',
    () async {
      final devices = _FakeDeviceService(installationIds);
      final registration = createRegistration(devices);
      await registration.start();
      await registration.unregister();

      pushTokens.refreshes.add('fcm-ignoré');
      await pumpEventQueue();
      await registration.register();
      expect(devices.registrations, hasLength(1));

      registration.completeSignOut();
      await registration.start();

      expect(devices.registrations.last, (
        installationId: 'installation-2',
        fcmToken: 'fcm-2',
      ));
    },
  );
}
