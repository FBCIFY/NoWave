import 'package:blueway/core/sensors/android_rotation_service.dart';
import 'package:blueway/core/sensors/camera_axis_service.dart';
import 'package:blueway/core/sensors/camera_azimuth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'carte et caméra partagent le canal ; NW-150 reçoit la matrice brute',
    () async {
      const channel = MethodChannel('fr.blueway.app/rotation_matrix');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var opened = 0;
      var closed = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listen') opened++;
        if (call.method == 'cancel') closed++;
        return null;
      });
      final samples = <AndroidRotationSample>[];
      final axes = <CameraAxis>[];
      final map = AndroidRotationService.samples.listen(samples.add);
      final camera = CameraAxisService().axis.listen(axes.add);
      await pumpEventQueue();
      expect(opened, 1);

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'matrix': <double>[1, 0, 0, 0, 0, -1, 0, 1, 0],
          'displayRotation': 1,
        }),
        (_) {},
      );
      await pumpEventQueue();
      expect(samples.single.displayRotation, 1);
      expect(axes.single, (east: 0.0, north: 1.0, up: 0.0));

      await map.cancel();
      expect(closed, 0);
      await camera.cancel();
      await pumpEventQueue();
      expect(closed, 1);

      final reopened = AndroidRotationService.samples.listen((_) {});
      await pumpEventQueue();
      expect(opened, 2);
      await reopened.cancel();
      await pumpEventQueue();
      expect(closed, 2);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
