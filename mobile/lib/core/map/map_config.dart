import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Réglages Mapbox partagés : jeton (lu dans `.env.json`), style de la carte
/// et masquage des éléments affichés par défaut.
class MapConfig {
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static const String styleUrl = 'mapbox://styles/mapbox/standard';

  /// Position de l'utilisateur : une flèche 3D qui pivote avec le cap du
  /// téléphone. Le modèle mesure une unité de long ; à l'échelle « viewport »,
  /// [_puckSize] est sa longueur en pixels, quel que soit le zoom.
  static LocationComponentSettings locationPuckSettings() =>
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
        locationPuck: LocationPuck(
          locationPuck3D: LocationPuck3D(
            modelUri: 'asset://assets/models/location_puck.glb',
            modelScale: [_puckSize, _puckSize, _puckSize],
            modelScaleMode: ModelScaleMode.VIEWPORT,
            modelRotation: [0, 0, _puckModelHeadingOffset],
            // Ombrage déjà peint dans le modèle : pas d'éclairage de la carte.
            modelEmissiveStrength: 1,
          ),
        ),
      );

  static const double _puckSize = 44;

  /// Le modèle pointe vers -Z (le nord glTF).
  static const double _puckModelHeadingOffset = 0;

  static Future<void> hideDefaultOrnaments(MapboxMap map) async {
    await Future.wait([
      map.compass.updateSettings(CompassSettings(enabled: false)),
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    ]);
  }
}
