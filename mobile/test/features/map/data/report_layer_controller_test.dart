import 'dart:async';

import 'package:blueway/features/map/data/report_layer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _tileError503 = 'Failed to load tile: HTTP status code 503';
const _tileError429 = 'Failed to load tile: HTTP status code 429';
const _tileError401 = 'Failed to load tile: HTTP status code 401';
const _tileErrorOffline = 'Failed to load tile: connection error';

/// Carte simulée : chaque installation réussit ou échoue selon [failInstall].
class _FakeMap {
  bool failInstall = false;
  int installs = 0;
  int authorizations = 0;
  int _running = 0;
  int maxConcurrentInstalls = 0;

  /// Installation qui ne se termine qu'à l'appel de [finishInstall].
  Completer<void>? blockedInstall;

  /// Token qui n'arrive qu'à l'appel de [finishAuthorize].
  Completer<void>? blockedAuthorize;

  /// Appels au réseau de Mapbox, coupure (false) ou rebranchement (true),
  /// dans l'ordre, échecs compris.
  final network = <bool>[];

  /// Réseau de Mapbox après le dernier appel réussi.
  bool mapboxConnected = true;

  /// Appel au réseau qui ne se termine qu'à l'appel de [finishNetwork].
  Completer<void>? blockedNetwork;

  /// Nombre de prochains appels au réseau refusés par Mapbox.
  int failNetwork = 0;

  late final controller = ReportLayerController(
    install: () async {
      installs++;
      _running++;
      if (_running > maxConcurrentInstalls) maxConcurrentInstalls = _running;
      try {
        final blocked = blockedInstall;
        if (blocked != null) await blocked.future;
        if (failInstall) throw Exception('token indisponible');
      } finally {
        _running--;
      }
    },
    authorize: () async {
      authorizations++;
      final blocked = blockedAuthorize;
      if (blocked != null) await blocked.future;
    },
    connectNetwork: (connected) async {
      network.add(connected);
      final blocked = blockedNetwork;
      if (blocked != null) await blocked.future;
      if (failNetwork > 0) {
        failNetwork--;
        throw Exception('OfflineSwitch indisponible');
      }
      mapboxConnected = connected;
    },
  );

  ReportLayerStatus get status => controller.status.value;

  void finishInstall() {
    final blocked = blockedInstall;
    blockedInstall = null;
    blocked?.complete();
  }

  void finishNetwork() {
    final blocked = blockedNetwork;
    blockedNetwork = null;
    blocked?.complete();
  }

  /// Termine le token en attente, en échec si [error] est donné.
  void finishAuthorize({Object? error}) {
    final blocked = blockedAuthorize;
    blockedAuthorize = null;
    if (error == null) {
      blocked?.complete();
    } else {
      blocked?.completeError(error);
    }
  }
}

void main() {
  late _FakeMap map;

  /// Test à minuteurs simulés ; le contrôleur est libéré avant la
  /// vérification des minuteurs restants.
  void testLayer(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      map = _FakeMap();
      await body(tester);
      map.controller.dispose();
    });
  }

  Future<void> install(WidgetTester tester) async {
    map.controller.styleLoaded();
    await tester.pump();
    expect(map.status, ReportLayerStatus.installed);
  }

  group('installation', () {
    testLayer('réussie au chargement du style', (tester) async {
      map.controller.styleLoaded();
      expect(map.status, ReportLayerStatus.pending);

      await tester.pump();

      expect(map.status, ReportLayerStatus.installed);
      expect(map.installs, 1);
    });

    testLayer(
      'token en échec puis retour réseau : réinstallée sans recharger le style',
      (tester) async {
        map.failInstall = true;
        map.controller.styleLoaded();
        await tester.pump();
        expect(map.status, ReportLayerStatus.notInstalled);

        map.failInstall = false;
        await tester.pump(const Duration(seconds: 14));
        expect(map.installs, 1);

        await tester.pump(const Duration(seconds: 1));
        expect(map.installs, 2);
        expect(map.status, ReportLayerStatus.installed);
      },
    );

    testLayer('retente après 15 s, 30 s, puis toutes les minutes', (
      tester,
    ) async {
      map.failInstall = true;
      map.controller.styleLoaded();
      await tester.pump();

      final installsAfter = <int>[];
      for (final seconds in [15, 30, 60, 60]) {
        await tester.pump(Duration(seconds: seconds));
        installsAfter.add(map.installs);
      }

      expect(installsAfter, [2, 3, 4, 5]);
      expect(map.status, ReportLayerStatus.notInstalled);
    });

    testLayer('retente tout de suite au retour dans l’app', (tester) async {
      map.failInstall = true;
      map.controller.styleLoaded();
      await tester.pump();
      map.controller.pause();

      await tester.pump(const Duration(minutes: 5));
      expect(map.installs, 1, reason: 'pas d’essai en arrière-plan');

      map.failInstall = false;
      map.controller.resume();
      await tester.pump();

      expect(map.installs, 2);
      expect(map.status, ReportLayerStatus.installed);
      expect(map.network, [false, true]);
    });

    testLayer('le renouvellement du token retente l’installation', (
      tester,
    ) async {
      map.failInstall = true;
      map.controller.styleLoaded();
      await tester.pump();

      map.failInstall = false;
      map.controller.renewToken();
      await tester.pump();

      expect(map.installs, 2);
      expect(map.authorizations, 0);
      expect(map.status, ReportLayerStatus.installed);
    });

    testLayer('un nouveau style annule la tentative programmée', (
      tester,
    ) async {
      map.failInstall = true;
      map.controller.styleLoaded();
      await tester.pump();

      map.failInstall = false;
      map.controller.styleLoaded();
      await tester.pump();
      expect(map.installs, 2);

      await tester.pump(const Duration(minutes: 2));
      expect(map.installs, 2);
      expect(map.status, ReportLayerStatus.installed);
    });

    testLayer('jamais deux installations en même temps', (tester) async {
      map.blockedInstall = Completer();
      map.controller.styleLoaded();
      await tester.pump();

      // Nouveau style et renouvellement pendant l'installation.
      map.controller.styleLoaded();
      map.controller.renewToken();
      await tester.pump();
      expect(map.installs, 1);

      map.finishInstall();
      await tester.pump();

      expect(map.maxConcurrentInstalls, 1);
      expect(
        map.installs,
        2,
        reason: 'une seule reprise pour le nouveau style',
      );
      expect(map.status, ReportLayerStatus.installed);
    });
  });

  group('tuiles', () {
    testLayer('429 ignorée : Mapbox redemande la tuile', (tester) async {
      await install(tester);
      await tester.pump(ReportLayerController.authorizeInterval);

      map.controller.tileError(_tileError429);

      expect(map.status, ReportLayerStatus.installed);
      expect(map.authorizations, 0);
    });

    testLayer('503 persistante : couche indisponible tant qu’elle dure', (
      tester,
    ) async {
      await install(tester);

      for (var i = 0; i < 10; i++) {
        map.controller.tileError(_tileError503);
        // Mapbox signale aussi la tuile en échec comme chargée.
        map.controller.tileLoaded();
        await tester.pump(const Duration(seconds: 1));
      }

      expect(map.status, ReportLayerStatus.unavailable);
    });

    testLayer('erreur puis tuile chargée : couche rétablie', (tester) async {
      await install(tester);
      map.controller.tileError(_tileError503);
      expect(map.status, ReportLayerStatus.unavailable);

      await tester.pump(ReportLayerController.recoveryQuietPeriod);
      map.controller.tileLoaded();
      expect(map.status, ReportLayerStatus.unavailable);

      await tester.pump(ReportLayerController.recoveryQuietPeriod);
      expect(map.status, ReportLayerStatus.installed);
    });

    testLayer('autre tuile chargée juste après l’erreur : couche rétablie', (
      tester,
    ) async {
      await install(tester);
      map.controller.tileError(_tileError503, tile: '12/1/1');
      await tester.pump(const Duration(milliseconds: 200));

      map.controller.tileLoaded(tile: '12/1/2');
      await tester.pump(ReportLayerController.recoveryQuietPeriod);
      expect(map.status, ReportLayerStatus.unavailable);

      await tester.pump(ReportLayerController.recoveryQuietPeriod);
      expect(map.status, ReportLayerStatus.installed);
    });

    testLayer('la tuile en échec signalée chargée ne rétablit rien', (
      tester,
    ) async {
      await install(tester);
      map.controller.tileError(_tileError503, tile: '12/1/1');
      map.controller.tileLoaded(tile: '12/1/1');

      await tester.pump(ReportLayerController.recoveryQuietPeriod * 3);

      expect(map.status, ReportLayerStatus.unavailable);
    });

    testLayer('une erreur juste après le chargement annule le retour', (
      tester,
    ) async {
      await install(tester);
      map.controller.tileError(_tileError503);
      await tester.pump(ReportLayerController.recoveryQuietPeriod);

      map.controller.tileLoaded();
      await tester.pump(const Duration(seconds: 1));
      map.controller.tileError(_tileError503);
      await tester.pump(ReportLayerController.recoveryQuietPeriod * 2);

      expect(map.status, ReportLayerStatus.unavailable);
    });

    testLayer('redonne le token au plus toutes les 30 s', (tester) async {
      await install(tester);
      await tester.pump(ReportLayerController.authorizeInterval);

      for (var i = 0; i < 20; i++) {
        map.controller.tileError(_tileError401);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(map.authorizations, 1);

      await tester.pump(const Duration(seconds: 10));
      map.controller.tileError(_tileError401);
      expect(map.authorizations, 2);
    });

    testLayer('seul un 401 redonne le token', (tester) async {
      await install(tester);
      await tester.pump(ReportLayerController.authorizeInterval);

      map.controller.tileError('Failed to load tile: HTTP status code 403');
      map.controller.tileError(_tileError503);
      map.controller.tileError(_tileError429);
      expect(map.authorizations, 0);

      map.controller.tileError(_tileError401);
      expect(map.authorizations, 1);
    });

    testLayer('un nouveau style repart d’un état propre', (tester) async {
      await install(tester);
      map.controller.tileError(_tileError503);
      expect(map.status, ReportLayerStatus.unavailable);

      map.controller.styleLoaded();
      expect(map.status, ReportLayerStatus.pending);
      await tester.pump();

      expect(map.status, ReportLayerStatus.installed);
    });
  });

  group('arrière-plan', () {
    testLayer('réseau coupé, puis rebranché après le token au retour', (
      tester,
    ) async {
      await install(tester);
      map.controller.pause();
      expect(map.network, [false]);
      expect(map.controller.networkCut, isTrue);

      map.blockedAuthorize = Completer();
      map.controller.resume();
      await tester.pump();
      expect(map.authorizations, 1);
      expect(map.network, [false], reason: 'aucune tuile avant le token');

      map.finishAuthorize();
      await tester.pump();
      expect(map.network, [false, true]);
      expect(map.controller.networkCut, isFalse);
    });

    testLayer('token en échec : réseau rebranché quand même', (tester) async {
      await install(tester);
      map.controller.pause();

      map.blockedAuthorize = Completer();
      map.controller.resume();
      map.finishAuthorize(error: Exception('hors ligne'));
      await tester.pump();

      expect(map.network, [false, true]);
    });

    testLayer('token trop lent : réseau rebranché sans l\'attendre', (
      tester,
    ) async {
      await install(tester);
      map.controller.pause();

      map.blockedAuthorize = Completer();
      map.controller.resume();
      await tester.pump(
        ReportLayerController.reconnectTimeout - const Duration(seconds: 1),
      );
      expect(map.network, [false]);

      await tester.pump(const Duration(seconds: 1));
      expect(map.network, [false, true]);
      expect(map.controller.networkCut, isFalse);
    });

    testLayer('repartie en arrière-plan avant le token : réseau coupé', (
      tester,
    ) async {
      await install(tester);
      map.controller.pause();

      map.blockedAuthorize = Completer();
      map.controller.resume();
      map.controller.pause();
      map.finishAuthorize();
      await tester.pump();

      expect(map.network, [false]);
      expect(map.controller.networkCut, isTrue);
    });

    testLayer('erreurs dues à la coupure ignorées', (tester) async {
      await install(tester);
      await tester.pump(ReportLayerController.authorizeInterval);
      map.controller.pause();

      map.controller.tileError(_tileErrorOffline, tile: '12/1/1');
      map.controller.tileError(_tileError401, tile: '12/1/2');

      expect(map.status, ReportLayerStatus.installed);
      expect(map.authorizations, 0);
    });

    testLayer('coupure lente puis retour : rebranché après la coupure', (
      tester,
    ) async {
      await install(tester);
      map.blockedNetwork = Completer();
      map.controller.pause();
      map.controller.resume();
      await tester.pump();
      expect(map.network, [false], reason: 'un appel à la fois');
      expect(map.controller.networkCut, isTrue);

      map.finishNetwork();
      await tester.pump();
      expect(map.network, [false, true]);
      expect(map.mapboxConnected, isTrue);
      expect(map.controller.networkCut, isFalse);
    });

    testLayer('coupure refusée : les erreurs de tuiles comptent', (
      tester,
    ) async {
      await install(tester);
      map.failNetwork = 1;
      map.controller.pause();
      await tester.pump();
      expect(map.controller.networkCut, isFalse);

      map.controller.tileError(_tileError503, tile: '12/1/1');
      expect(map.status, ReportLayerStatus.unavailable);

      await tester.pump(ReportLayerController.networkRetryDelay);
      expect(map.network, [false, false]);
      expect(map.mapboxConnected, isFalse);
      expect(map.controller.networkCut, isTrue);
    });

    testLayer('rebranchement refusé : retenté', (tester) async {
      await install(tester);
      map.controller.pause();
      map.failNetwork = 1;
      map.controller.resume();
      await tester.pump();
      expect(map.network, [false, true]);
      expect(map.controller.networkCut, isTrue, reason: 'toujours coupé');

      await tester.pump(ReportLayerController.networkRetryDelay);
      expect(map.network, [false, true, true]);
      expect(map.mapboxConnected, isTrue);
      expect(map.controller.networkCut, isFalse);
    });

    testWidgets('carte fermée en arrière-plan : réseau rebranché', (
      tester,
    ) async {
      final closed = _FakeMap();
      closed.controller.pause();

      closed.controller.dispose();
      await tester.pump();

      expect(closed.network, [false, true]);
    });
  });

  test('reconnaît la limite de débit, pas les pannes', () {
    const prefix = 'Failed to load tile: HTTP status code';

    expect(ReportLayerController.isRateLimited('$prefix 429'), isTrue);
    expect(ReportLayerController.isRateLimited('$prefix 503'), isFalse);
    expect(ReportLayerController.isRateLimited('$prefix 401'), isFalse);
    expect(ReportLayerController.isRateLimited('$prefix 4290'), isFalse);
  });

  test('reconnaît un token refusé', () {
    const prefix = 'Failed to load tile: HTTP status code';

    expect(ReportLayerController.isUnauthorized('$prefix 401'), isTrue);
    expect(ReportLayerController.isUnauthorized('$prefix 403'), isFalse);
    expect(ReportLayerController.isUnauthorized('$prefix 4010'), isFalse);
  });
}
