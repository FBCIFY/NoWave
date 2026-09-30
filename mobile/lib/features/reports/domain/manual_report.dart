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
class ManualReportRequest {
  const ManualReportRequest({
    required this.clientReportId,
    required this.category,
    required this.longitude,
    required this.latitude,
    required this.observedAt,
    this.description,
  });

  final String clientReportId;
  final ReportCategory category;
  final double longitude;
  final double latitude;
  final DateTime observedAt;
  final String? description;

  bool matchesContent({
    required ReportCategory category,
    required double longitude,
    required double latitude,
    required String? description,
  }) =>
      this.category == category &&
      this.longitude == longitude &&
      this.latitude == latitude &&
      this.description == description;

  Map<String, Object?> toJson() => {
    'client_report_id': clientReportId,
    'category': category.apiValue,
    'description': description,
    'final_position': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
    'observed_at': observedAt.toUtc().toIso8601String(),
  };
}
