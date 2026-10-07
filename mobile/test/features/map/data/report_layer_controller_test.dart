import 'dart:async';

import 'package:blueway/features/map/data/report_layer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _tileError503 = 'Failed to load tile: HTTP status code 503';
const _tileError429 = 'Failed to load tile: HTTP status code 429';

/// Carte simulée : chaque installation réussit ou échoue selon [failInstall].
class _FakeMap {
  bool failInstall = false;
  int installs = 0;
  int authorizations = 0;
  int _running = 0;
  int maxConcurrentInstalls = 0;

  /// Installation qui ne se termine qu'à l'appel de [finishInstall].
  Completer<void>? blockedInstall;

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
    authorize: () async => authorizations++,
  );

  ReportLayerStatus get status => controller.status.value;

  void finishInstall() {
    final blocked = blockedInstall;
    blockedInstall = null;
    blocked?.complete();
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
    Future<void> install(WidgetTester tester) async {
      map.controller.styleLoaded();
      await tester.pump();
      expect(map.status, ReportLayerStatus.installed);
    }

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
        map.controller.tileError('Failed to load tile: HTTP status code 401');
        await tester.pump(const Duration(seconds: 1));
      }
      expect(map.authorizations, 1);

      await tester.pump(const Duration(seconds: 10));
      map.controller.tileError('Failed to load tile: HTTP status code 401');
      expect(map.authorizations, 2);
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

  test('reconnaît la limite de débit, pas les pannes', () {
    const prefix = 'Failed to load tile: HTTP status code';

    expect(ReportLayerController.isRateLimited('$prefix 429'), isTrue);
    expect(ReportLayerController.isRateLimited('$prefix 503'), isFalse);
    expect(ReportLayerController.isRateLimited('$prefix 401'), isFalse);
    expect(ReportLayerController.isRateLimited('$prefix 4290'), isFalse);
  });
}
