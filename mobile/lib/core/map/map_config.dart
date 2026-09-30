import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Réglages Mapbox partagés : jeton (lu dans `.env.json`), style de la carte
/// et masquage des éléments affichés par défaut.
class MapConfig {
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static const String styleUrl = 'mapbox://styles/mapbox/standard';

  static Future<void> hideDefaultOrnaments(MapboxMap map) async {
    await Future.wait([
      map.compass.updateSettings(CompassSettings(enabled: false)),
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    ]);
  }
}
