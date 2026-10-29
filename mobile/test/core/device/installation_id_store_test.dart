import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blueway/core/device/installation_id_store.dart';

class _Preferences extends Fake implements SharedPreferences {
  String? value = 'installation-1';
  bool refuseRemove = false;
  Future<void>? removeResponse;

  @override
  String? getString(String key) => value;

  @override
  Future<bool> setString(String key, String value) async {
    this.value = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await removeResponse;
    if (refuseRemove) return false;
    value = null;
    return true;
  }
}

void main() {
  late int created;

  InstallationIdStore createStore() {
    return InstallationIdStore(newId: () => 'installation-${++created}');
  }

  setUp(() {
    created = 0;
    SharedPreferences.setMockInitialValues({});
  });

  test('crée un identifiant au premier appel puis le réutilise', () async {
    final store = createStore();

    expect(await store.read(), 'installation-1');
    expect(await store.read(), 'installation-1');
    expect(created, 1);
  });

  test('garde l’identifiant après un redémarrage de l’app', () async {
    await createStore().read();

    expect(await createStore().read(), 'installation-1');
    expect(created, 1);
  });

  test('deux lectures simultanées partagent le même identifiant', () async {
    final store = createStore();

    final ids = await Future.wait([store.read(), store.read()]);

    expect(ids, ['installation-1', 'installation-1']);
    expect(created, 1);
  });

  test('reset donne un nouvel identifiant, même après redémarrage', () async {
    final store = createStore();
    await store.read();

    await store.reset();

    expect(await store.read(), 'installation-2');
    expect(await createStore().read(), 'installation-2');
  });

  test('réessaie après une lecture ratée', () async {
    var failures = 1;
    final store = InstallationIdStore(
      preferences: () async {
        if (failures-- > 0) throw StateError('stockage indisponible');
        return SharedPreferences.getInstance();
      },
      newId: () => 'installation-${++created}',
    );

    await expectLater(store.read(), throwsStateError);
    expect(await store.read(), 'installation-1');
  });

  test(
    'une suppression refusée conserve l’identifiant et peut être réessayée',
    () async {
      final preferences = _Preferences()..refuseRemove = true;
      final store = InstallationIdStore(
        preferences: () async => preferences,
        newId: () => 'installation-2',
      );
      await store.read();

      await expectLater(store.reset(), throwsStateError);
      expect(await store.read(), 'installation-1');
      expect(preferences.value, 'installation-1');

      preferences.refuseRemove = false;
      await store.reset();
      expect(await store.read(), 'installation-2');
      expect(preferences.value, 'installation-2');
    },
  );

  test('une lecture pendant reset attend la suppression avant de créer '
      'l’identifiant suivant', () async {
    final response = Completer<void>();
    final preferences = _Preferences()..removeResponse = response.future;
    final store = InstallationIdStore(
      preferences: () async => preferences,
      newId: () => 'installation-2',
    );
    await store.read();

    final resetting = store.reset();
    final nextId = store.read();
    await pumpEventQueue();
    expect(preferences.value, 'installation-1');
    response.complete();
    await resetting;

    expect(await nextId, 'installation-2');
    expect(preferences.value, 'installation-2');
  });
}
