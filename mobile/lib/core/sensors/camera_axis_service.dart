import 'android_rotation_service.dart';
import 'camera_azimuth.dart';

/// Axe de visée de la caméra arrière en continu, sur Android (NW-150).
///
/// Lit le capteur de rotation fusionné (le même que `precise_compass`) via
/// le canal natif de `MainActivity`. Sur iOS, le cap de CoreLocation suffit.
class CameraAxisService {
  CameraAxisService({Stream<List<double>>? rotationMatrices})
    : _rotationMatrices =
          rotationMatrices ??
          AndroidRotationService.samples.map((sample) => sample.matrix);

  /// Même lissage que l'inclinaison : environ 0,15 s à 50 Hz.
  static const smoothingFactor = 0.12;

  final Stream<List<double>> _rotationMatrices;

  Stream<CameraAxis> get axis => Stream<CameraAxis>.multi((controller) {
    CameraAxis? smoothed;
    final subscription = _rotationMatrices.listen(
      (matrix) {
        final measured = cameraAxisFromRotationMatrix(matrix);
        final previous = smoothed;
        // On lisse le vecteur, pas l'angle : pas de saut entre 359° et 0°.
        smoothed = previous == null
            ? measured
            : (
                east: _smooth(previous.east, measured.east),
                north: _smooth(previous.north, measured.north),
                up: _smooth(previous.up, measured.up),
              );
        controller.add(smoothed!);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    // Libère immédiatement l'abonné caméra, même sans nouvelle mesure ;
    // la carte peut continuer à écouter le canal partagé.
    controller.onCancel = subscription.cancel;
  });

  static double _smooth(double previous, double measured) =>
      previous + smoothingFactor * (measured - previous);
}
