import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blueway/core/device/installation_id_store.dart';

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
}
