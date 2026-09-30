/// Précision GPS minimale pour autoriser une photo.
const double maxCaptureGpsAccuracyMeters = 50;

bool isCaptureGpsAccuracySufficient(double? accuracyMeters) {
  return accuracyMeters != null &&
      accuracyMeters <= maxCaptureGpsAccuracyMeters;
}

/// Hauteur de l'objectif au-dessus de l'eau, fixée pour le MVP.
const double defaultCameraHeightMeters = 2.5;
const double defaultCameraHeightUncertaintyMeters = 0.5;
const String defaultCameraHeightSource = 'default';
