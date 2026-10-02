import '../../camera/domain/photo_capture.dart';

/// Catégories proposées ; [apiValue] est la valeur attendue par le backend.
enum ReportCategory {
  marineAnimal('marine_animal'),
  obstruction('obstruction'),
  pollution('pollution');

  const ReportCategory(this.apiValue);

  final String apiValue;
}

/// Signalement à envoyer. `clientReportId` est généré par l'app et réutilisé
/// si l'envoi est retenté avec le même contenu.
///
/// Avec [positioning], le signalement part en mode photo : le backend garde
/// les mesures de la photo à côté du point confirmé par l'utilisateur.
class ManualReportRequest {
  const ManualReportRequest({
    required this.clientReportId,
    required this.category,
    required this.longitude,
    required this.latitude,
    required this.observedAt,
    this.description,
    this.positioning,
  });

  final String clientReportId;
  final ReportCategory category;
  final double longitude;
  final double latitude;
  final DateTime observedAt;
  final String? description;
  final PhotoCaptureMeasurements? positioning;

  bool matchesContent({
    required ReportCategory category,
    required double longitude,
    required double latitude,
    required String? description,
    PhotoCaptureMeasurements? positioning,
  }) =>
      this.category == category &&
      this.longitude == longitude &&
      this.latitude == latitude &&
      this.description == description &&
      // Mêmes mesures = même photo : une nouvelle photo change de signalement.
      identical(this.positioning, positioning);

  Map<String, Object?> toJson() => {
    'client_report_id': clientReportId,
    'category': category.apiValue,
    'description': description,
    'final_position': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
    'observed_at': observedAt.toUtc().toIso8601String(),
    if (positioning != null) ...{
      'positioning_mode': 'photo',
      'positioning': positioning!.toJson(),
    },
  };
}
