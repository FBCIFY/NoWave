import 'package:blueway/core/sensors/camera_axis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lisse le vecteur de visée pour passer de 359° à 1° sans détour',
    () async {
      // Caméra visant presque plein nord, juste à l'ouest puis juste à l'est.
      const west = [1.0, 0.0, 0.0174, 0.0, 0.0, -0.9998, 0.0, 1.0, 0.0];
      const east = [1.0, 0.0, -0.0174, 0.0, 0.0, -0.9998, 0.0, 1.0, 0.0];
      final service = CameraAxisService(
        rotationMatrices: Stream.fromIterable([west, east]),
      );

      final axes = await service.axis.toList();

      expect(axes, hasLength(2));
      expect(axes.first.east, closeTo(-0.0174, 1e-9));
      // Le lissage rapproche l'est de 0, sans passer par le sud.
      expect(axes.last.east, closeTo(-0.0174 + 0.12 * 0.0348, 1e-9));
      expect(axes.last.north, closeTo(0.9998, 1e-9));
    },
  );
}
