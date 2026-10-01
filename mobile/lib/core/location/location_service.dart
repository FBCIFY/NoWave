import 'package:geolocator/geolocator.dart';

/// Position GPS du téléphone.
class LocationService {
  /// Récupère la position une fois, en demandant l'autorisation si besoin.
  ///
  /// Lève une [StateError] avec un message prêt à afficher si la localisation
  /// est désactivée ou refusée.
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw StateError(
        'La localisation est désactivée. Activez-la dans les réglages.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw StateError('L’accès à votre position a été refusé.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'L’accès à votre position est bloqué. Autorisez-le dans les réglages.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Suivi continu, une fois l'autorisation obtenue par [getCurrentPosition].
  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }
}
