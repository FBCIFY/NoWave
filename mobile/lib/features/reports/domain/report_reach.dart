import 'dart:math' as math;

/// Zone où l'on peut poser un signalement : ce que l'œil voit depuis le pont.
/// Calcul sur une sphère, assez précis à l'échelle du kilomètre.
class ReportReach {
  static const radiusMeters = 1000.0;
  static const _earthRadius = 6371008.8;

  /// Distance en mètres entre deux points (latitude, longitude en degrés).
  static double distance(
    double fromLatitude,
    double fromLongitude,
    double toLatitude,
    double toLongitude,
  ) {
    final lat1 = _radians(fromLatitude);
    final lat2 = _radians(toLatitude);
    final dLat = lat2 - lat1;
    final dLon = _radians(toLongitude - fromLongitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Le point lui-même s'il est dans la zone, sinon le bord de la zone dans
  /// la même direction depuis l'origine.
  static ({double latitude, double longitude}) clamp(
    double originLatitude,
    double originLongitude,
    double latitude,
    double longitude,
  ) {
    final meters = distance(
      originLatitude,
      originLongitude,
      latitude,
      longitude,
    );
    if (meters <= radiusMeters) {
      return (latitude: latitude, longitude: longitude);
    }
    final lat1 = _radians(originLatitude);
    final lat2 = _radians(latitude);
    final dLon = _radians(longitude - originLongitude);
    final bearing = math.atan2(
      math.sin(dLon) * math.cos(lat2),
      math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(dLon),
    );
    // Un mètre de marge : l'arrondi ne doit pas ressortir le point.
    return destination(
      originLatitude,
      originLongitude,
      bearing,
      radiusMeters - 1,
    );
  }

  /// Point atteint depuis l'origine dans la direction donnée (radians, 0 = nord).
  static ({double latitude, double longitude}) destination(
    double latitude,
    double longitude,
    double bearing,
    double meters,
  ) {
    final lat1 = _radians(latitude);
    final angle = meters / _earthRadius;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angle) +
          math.cos(lat1) * math.sin(angle) * math.cos(bearing),
    );
    final lon2 =
        _radians(longitude) +
        math.atan2(
          math.sin(bearing) * math.sin(angle) * math.cos(lat1),
          math.cos(angle) - math.sin(lat1) * math.sin(lat2),
        );
    return (
      latitude: lat2 * 180 / math.pi,
      longitude: ((lon2 * 180 / math.pi) + 540) % 360 - 180,
    );
  }

  /// Rectangle qui entoure la zone, pour borner la caméra.
  static ({double south, double west, double north, double east}) bounds(
    double latitude,
    double longitude,
  ) {
    final north = destination(latitude, longitude, 0, radiusMeters);
    final east = destination(latitude, longitude, math.pi / 2, radiusMeters);
    final south = destination(latitude, longitude, math.pi, radiusMeters);
    final west = destination(latitude, longitude, -math.pi / 2, radiusMeters);
    return (
      south: south.latitude,
      west: west.longitude,
      north: north.latitude,
      east: east.longitude,
    );
  }

  /// Contour fermé de la zone, pour l'afficher sur la carte.
  static List<List<double>> outline(double latitude, double longitude) => [
    for (var step = 0; step <= 72; step++)
      () {
        final point = destination(
          latitude,
          longitude,
          step * 2 * math.pi / 72,
          radiusMeters,
        );
        return [point.longitude, point.latitude];
      }(),
  ];

  static double _radians(double degrees) => degrees * math.pi / 180;
}
