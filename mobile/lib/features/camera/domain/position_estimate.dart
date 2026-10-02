/// Position de l'objet visé, calculée par le backend à partir des mesures
/// de la photo. L'utilisateur la confirme ou la corrige avant publication.
class PositionEstimate {
  const PositionEstimate({
    required this.longitude,
    required this.latitude,
    required this.distanceMeters,
  });

  final double longitude;
  final double latitude;

  /// Distance entre le téléphone et l'objet.
  final double distanceMeters;

  /// Lit la réponse de `POST api/v1/position-estimates`. Renvoie null quand
  /// le backend ne peut pas estimer (visée au-dessus de l'horizon, par
  /// exemple) : l'utilisateur place alors le point lui-même.
  static PositionEstimate? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException("L'estimation reçue est invalide.");
    }

    final position = json['estimated_position'];
    final distance = json['estimated_distance_m'];

    if (position == null) {
      return null;
    }

    final coordinates = position is Map<String, dynamic>
        ? position['coordinates']
        : null;

    if (coordinates is! List ||
        coordinates.length != 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num ||
        distance is! num) {
      throw const FormatException("L'estimation reçue est invalide.");
    }

    return PositionEstimate(
      longitude: (coordinates[0] as num).toDouble(),
      latitude: (coordinates[1] as num).toDouble(),
      distanceMeters: distance.toDouble(),
    );
  }
}
