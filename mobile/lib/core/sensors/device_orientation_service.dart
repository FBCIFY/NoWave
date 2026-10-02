import 'package:precise_compass/precise_compass.dart';

/// Flux continu du cap (par rapport au nord géographique), du tangage et du
/// roulis du téléphone. Utilisé par la boussole de la carte et par la caméra.
class DeviceOrientationService {
  /// Un seul flux pour toute l'app : chaque flux du plugin ouvre le même canal
  /// natif, et un second abonné (la caméra ouverte par-dessus la carte) coupait
  /// le premier. Partagé, le capteur s'arrête seulement quand plus personne
  /// n'écoute.
  static final Stream<CompassReading> _readings = PreciseCompass.headingStream(
    config: const CompassConfig(
      reference: HeadingReference.trueNorth,
      rate: SensorRate.normal,
    ),
  );

  Stream<CompassReading> get readings => _readings;
}
