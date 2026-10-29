import 'dart:convert';

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

  /// Process-wide native budget per host, shared by raster and basemap sources.
  /// The two Dart GeoJSON workers have their own independent request budget.
  static const maxRequestsPerHost = 2;

  static Future<void> configureNetwork(MapboxMap map) async {
    try {
      await map.httpService.setMaxRequestsPerHost(maxRequestsPerHost);
    } catch (error) {
      debugPrint('Limite réseau Mapbox indisponible : $error');
    }
  }

  static Future<void> prepareStyle() async {
    try {
      styleUrl = await GlobeStyle.prepare();
    } catch (error) {
      debugPrint('Style globe indisponible, fond Standard conservé : $error');
    }
  }

  /// Taille réduite de loin, taille normale de près.
  static const double detailedPuckMinZoom = 9;

  /// Essai : la flèche 3D orange est le repère natif de Mapbox, dessiné et
  /// orienté à chaque image sans passer par Dart. false revient au chevron et
  /// au mât de LocationMarker.
  static const bool nativeArrowPuck = true;

  /// Longueur de la flèche en points : le modèle mesure une unité de long et
  /// l'échelle « viewport » compte en pixels écran. [_arrowSize] dès le zoom
  /// [_arrowFullZoom], [_arrowFarSize] au zoom [_arrowFarZoom] et en deçà :
  /// carte entièrement dézoomée, l'Europe ne fait qu'une cinquantaine de
  /// points de large.
  static const double _arrowSize = 27.44;
  static const double _arrowFullZoom = 6;
  static const double _arrowFarSize = 13.72;
  static const double _arrowFarZoom = 2;

  /// Le composant natif reste actif pour FollowPuckViewportState. Sans
  /// [arrow], le repère visible est dessiné par LocationMarker avec le cap de
  /// la boussole.
  static LocationComponentSettings locationPuckSettings({
    bool arrow = nativeArrowPuck,
  }) => arrow
      ? LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
          pulsingEnabled: false,
          // Halo de précision blanc translucide, si Mapbox l'affiche sous un
          // repère 3D.
          showAccuracyRing: true,
          accuracyRingColor: 0x33FFFFFF,
          accuracyRingBorderColor: 0x669CA3AF,
          locationPuck: LocationPuck(
            locationPuck3D: LocationPuck3D(
              modelUri: 'asset://assets/models/location_puck.glb',
              modelScaleMode: ModelScaleMode.VIEWPORT,
              modelScaleExpression: arrowScaleExpression,
              // Le modèle pointe vers -Z, le nord glTF.
              modelRotation: [0, 0, 0],
              // Ombrage déjà peint dans le modèle : pas d'éclairage de la
              // carte.
              modelEmissiveStrength: 1,
              modelCastShadows: false,
              modelReceiveShadows: false,
            ),
          ),
        )
      : LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: false,
          pulsingEnabled: false,
          showAccuracyRing: false,
          locationPuck: LocationPuck(
            locationPuck2D: LocationPuck2D(
              // null conserve les images précédentes sur Android, dont le
              // point bleu par défaut. Des tableaux vides les retirent
              // explicitement.
              topImage: Uint8List(0),
              bearingImage: Uint8List(0),
              shadowImage: Uint8List(0),
              opacity: 0,
            ),
          ),
        );

  /// Taille fixe de près, qui diminue au dézoom jusqu'au zoom
  /// [_arrowFarZoom]. Évaluée par Mapbox, sans appel Dart au zoom.
  @visibleForTesting
  static final String arrowScaleExpression = jsonEncode([
    'interpolate',
    ['linear'],
    ['zoom'],
    _arrowFarZoom,
    ['literal', List.filled(3, _arrowFarSize)],
    _arrowFullZoom,
    ['literal', List.filled(3, _arrowSize)],
  ]);

  static Future<void> hideDefaultOrnaments(MapboxMap map) async {
    await Future.wait([
      map.compass.updateSettings(CompassSettings(enabled: false)),
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    ]);
  }

  /// Double tap + glissé : Mapbox zoome sans que l'utilisateur le veuille.
  /// Le zoom à un doigt passe par les bords de l'écran (MapEdgeZoom).
  static Future<void> disableQuickZoom(MapboxMap map) =>
      updateGestures(map, GesturesSettings(quickZoomEnabled: false));

  /// Réglage partiel des gestes : les champs laissés à null ne changent pas.
  static Future<void> updateGestures(
    MapboxMap map,
    GesturesSettings settings,
  ) async {
    try {
      await map.gestures.updateSettings(settings);
    } catch (_) {
      // Gestes non réglables : Mapbox garde les réglages précédents.
    }
  }
}
