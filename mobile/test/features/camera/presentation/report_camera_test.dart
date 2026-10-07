import 'dart:async';

import 'package:blueway/features/camera/presentation/report_camera.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// Contrôleur dont on décide quand l'ouverture se termine.
class _FakeController extends CameraController {
  _FakeController() : super(_backCamera, ResolutionPreset.low);

  final opening = Completer<void>();
  bool isLocked = false;
  int disposals = 0;

  @override
  Future<void> initialize() => opening.future;

  @override
  Future<void> lockCaptureOrientation([DeviceOrientation? orientation]) async {
    isLocked = true;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    // Ouverture simulée : le plugin n'a rien à libérer côté téléphone.
    if (disposals == 1) super.dispose();
  }
}

void main() {
  test(
    'écran fermé pendant la recherche des caméras : aucun contrôleur',
    () async {
      final search = Completer<List<CameraDescription>>();
      var created = 0;
      final camera = DeviceReportCamera(
        findCameras: () => search.future,
        createController: (_) {
          created++;
          return _FakeController();
        },
      );

      final opening = camera.initialize();
      await camera.dispose();
      search.complete([_backCamera]);
      await opening;

      expect(created, 0);
    },
  );

  test(
    'écran fermé pendant l’ouverture : le contrôleur est libéré ensuite',
    () async {
      final controller = _FakeController();
      final camera = DeviceReportCamera(
        findCameras: () async => [_backCamera],
        createController: (_) => controller,
      );

      final opening = camera.initialize();
      await pumpEventQueue();
      await camera.dispose();
      expect(controller.disposals, 0);

      controller.opening.complete();
      await opening;

      expect(controller.disposals, 1);
      expect(controller.isLocked, isFalse);
    },
  );

  test(
    'ouverture en échec après la fermeture : pas d’erreur, contrôleur libéré',
    () async {
      final controller = _FakeController();
      final camera = DeviceReportCamera(
        findCameras: () async => [_backCamera],
        createController: (_) => controller,
      );

      final opening = camera.initialize();
      await pumpEventQueue();
      await camera.dispose();
      controller.opening.completeError(
        CameraException('CameraAccessDenied', null),
      );

      await expectLater(opening, completes);
      expect(controller.disposals, 1);
    },
  );

  test(
    'ouverture en échec : l’erreur remonte et le contrôleur est libéré',
    () async {
      final controller = _FakeController();
      final camera = DeviceReportCamera(
        findCameras: () async => [_backCamera],
        createController: (_) => controller,
      );

      final opening = camera.initialize();
      await pumpEventQueue();
      controller.opening.completeError(
        CameraException('CameraAccessDenied', null),
      );

      await expectLater(
        opening,
        throwsA(
          isA<CameraException>().having(
            (e) => e.code,
            'code',
            'CameraAccessDenied',
          ),
        ),
      );
      expect(controller.disposals, 1);
    },
  );

  test(
    'ouverture normale : portrait verrouillé, libéré une seule fois',
    () async {
      final controller = _FakeController()..opening.complete();
      final camera = DeviceReportCamera(
        findCameras: () async => [_backCamera],
        createController: (_) => controller,
      );

      await camera.initialize();
      expect(controller.isLocked, isTrue);

      await camera.dispose();
      await camera.dispose();
      expect(controller.disposals, 1);
    },
  );

  test('photo demandée après la libération : CameraException', () async {
    final camera = DeviceReportCamera(
      findCameras: () async => [_backCamera],
      createController: (_) => _FakeController()..opening.complete(),
    );
    await camera.initialize();
    await camera.dispose();

    await expectLater(
      camera.takePicture(),
      throwsA(
        isA<CameraException>().having(
          (e) => e.code,
          'code',
          ReportCamera.closedCode,
        ),
      ),
    );
  });
}
