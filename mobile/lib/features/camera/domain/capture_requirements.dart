/// Précision GPS minimale pour autoriser une photo.
const double maxCaptureGpsAccuracyMeters = 50;

bool isCaptureGpsAccuracySufficient(double? accuracyMeters) {
  return accuracyMeters != null &&
      accuracyMeters <= maxCaptureGpsAccuracyMeters;
}
