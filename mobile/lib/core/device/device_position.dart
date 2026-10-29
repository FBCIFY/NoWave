/// Mesure GPS du téléphone, envoyée au backend pour choisir qui reçoit les
/// alertes à proximité. Sans lien avec la zone affichée sur la carte.
class DevicePosition {
  /// Au-delà, la mesure est trop imprécise pour les alertes et n'est pas
  /// envoyée : le backend garde la dernière position valide.
  static const double maxAccuracyM = 50;

  final double latitude;
  final double longitude;
  final double accuracyM;

  /// Cap suivi en degrés (0 ≤ cap < 360), ou `null` si inconnu.
  final double? headingDeg;
  final DateTime measuredAt;

  const DevicePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.measuredAt,
    this.headingDeg,
  });

  /// Vrai si la mesure peut servir aux alertes : coordonnées valides et
  /// précision connue, d'au plus [maxAccuracyM].
  bool get isUsable =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      accuracyM.isFinite &&
      accuracyM >= 0 &&
      accuracyM <= maxAccuracyM;

  Map<String, Object?> toJson() {
    return {
      'position': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
      'accuracy_m': accuracyM,
      'heading_deg': headingDeg,
      'measured_at': measuredAt.toUtc().toIso8601String(),
    };
  }
}
