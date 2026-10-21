import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'globe_style.dart';

/// Réglages Mapbox partagés : jeton (lu dans `.env.json`), style de la carte
/// et masquage des éléments affichés par défaut.
class MapConfig {
  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static String styleUrl = 'mapbox://styles/mapbox/standard';

  static Future<void> prepareStyle() async {
    try {
      styleUrl = await GlobeStyle.prepare();
    } catch (error) {
      debugPrint('Style globe indisponible, fond Standard conservé : $error');
    }
  }

  /// Taille réduite de loin, taille normale de près.
  static const double detailedPuckMinZoom = 9;

  /// Le composant natif reste actif pour FollowPuckViewportState. Le repère
  /// visible est dessiné par LocationMarker avec le cap de la boussole.
  static LocationComponentSettings locationPuckSettings() =>
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: false,
        pulsingEnabled: false,
        showAccuracyRing: false,
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(
            // null conserve les images précédentes sur Android, dont le point
            // bleu par défaut. Des tableaux vides les retirent explicitement.
            topImage: Uint8List(0),
            bearingImage: Uint8List(0),
            shadowImage: Uint8List(0),
            opacity: 0,
          ),
        ),
      );

  static Future<void> hideDefaultOrnaments(MapboxMap map) async {
    await Future.wait([
      map.compass.updateSettings(CompassSettings(enabled: false)),
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    ]);
  }

  /// Double tap + glissé : Mapbox zoome sans que l'utilisateur le veuille.
  /// Le zoom à un doigt passe par les bords de l'écran (MapEdgeZoom).
  static Future<void> disableQuickZoom(MapboxMap map) async {
    try {
      await map.gestures.updateSettings(
        GesturesSettings(quickZoomEnabled: false),
      );
    } catch (_) {
      // Gestes non réglables : le double tap + glissé reste actif.
    }
  }
}
