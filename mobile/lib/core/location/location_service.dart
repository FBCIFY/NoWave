import 'package:geolocator/geolocator.dart';

/// Récupère la position GPS une fois, en demandant l'autorisation si besoin.
///
/// Lève une [StateError] avec un message prêt à afficher si la localisation
/// est désactivée ou refusée.
class LocationService {
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
}
