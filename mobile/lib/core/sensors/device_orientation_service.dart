import 'package:precise_compass/precise_compass.dart';

/// Flux continu du cap (par rapport au nord géographique), du tangage et du
/// roulis du téléphone. Utilisé par la boussole de la carte et par la caméra.
class DeviceOrientationService {
  Stream<CompassReading> get readings {
    return PreciseCompass.headingStream(
      config: const CompassConfig(
        reference: HeadingReference.trueNorth,
        rate: SensorRate.normal,
      ),
    );
  }
}
