import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Réglages Mapbox partagés : jeton (lu dans `.env.json`), style de la carte
/// et masquage des éléments affichés par défaut.
class MapConfig {
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static const String styleUrl = 'mapbox://styles/mapbox/standard';

  /// Zoom à partir duquel la flèche 3D remplace le point bleu : le même
  /// seuil que les badges des signalements.
  static const double detailedPuckMinZoom = 9;

  /// Position de l'utilisateur. De près, une flèche 3D qui pivote avec le cap
  /// du téléphone ; le modèle mesure une unité de long et, à l'échelle
  /// « viewport », [_puckSize] est sa longueur en pixels quel que soit le
  /// zoom. De loin ([zoomedOut]), le point bleu de Mapbox, plus discret : la
  /// flèche couvrirait toute une région.
  static LocationComponentSettings locationPuckSettings({
    bool zoomedOut = false,
  }) => LocationComponentSettings(
    enabled: true,
    puckBearingEnabled: true,
    puckBearing: PuckBearing.HEADING,
    locationPuck: zoomedOut
        ? LocationPuck(locationPuck2D: DefaultLocationPuck2D())
        : LocationPuck(
            locationPuck3D: LocationPuck3D(
              modelUri: 'asset://assets/models/location_puck.glb',
              modelScale: [_puckSize, _puckSize, _puckSize],
              modelScaleMode: ModelScaleMode.VIEWPORT,
              modelRotation: [0, 0, _puckModelHeadingOffset],
              // Ombrage déjà peint dans le modèle : pas d'éclairage de la
              // carte.
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
