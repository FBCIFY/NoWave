/// Précision GPS minimale pour autoriser une photo.
const double maxCaptureGpsAccuracyMeters = 50;

/// Le GPS peut arriver moins souvent que les capteurs continus.
const maxCaptureGpsAge = Duration(seconds: 15);
const maxCaptureSensorAge = Duration(seconds: 5);

bool isCaptureMeasurementFresh(
  DateTime? measuredAt,
  DateTime now,
  Duration maxAge,
) {
  if (measuredAt == null) return false;
  final age = now.difference(measuredAt);
  // Petite tolérance entre les horloges natives et Dart, sans accepter une
  // position arbitrairement datée dans le futur.
  return age >= const Duration(seconds: -2) && age <= maxAge;
}

bool isCaptureGpsAccuracySufficient(double? accuracyMeters) {
  return accuracyMeters != null &&
      accuracyMeters.isFinite &&
      accuracyMeters >= 0 &&
      accuracyMeters <= maxCaptureGpsAccuracyMeters;
}

/// Hauteur de l'objectif au-dessus de l'eau, fixée pour le MVP.
const double defaultCameraHeightMeters = 2.5;
const double defaultCameraHeightUncertaintyMeters = 0.5;
const String defaultCameraHeightSource = 'default';
