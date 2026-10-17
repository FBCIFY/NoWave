import 'package:flutter/services.dart';

/// Matrice brute appareil → est/nord magnétique/haut, sans remapping écran.
class AndroidRotationSample {
  const AndroidRotationSample(this.matrix, {this.displayRotation = 0});

  factory AndroidRotationSample.fromEvent(dynamic event) {
    final data = event as Map;
    return AndroidRotationSample(
      (data['matrix'] as List).cast<double>(),
      displayRotation: data['displayRotation'] as int,
    );
  }

  final List<double> matrix;

  /// Constante Surface.ROTATION_* (0, 1, 2 ou 3), relative à l'orientation
  /// naturelle de l'appareil, qui peut être paysage sur une tablette.
  final int displayRotation;
}

class AndroidRotationService {
  // receiveBroadcastStream est déjà partagé et refermable. Une seule instance
  // empêche la caméra et la carte d'ouvrir deux fois le même canal natif.
  static final samples = const EventChannel('fr.blueway.app/rotation_matrix')
      .receiveBroadcastStream()
      .map(AndroidRotationSample.fromEvent);
}
