import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Habillage marin commun de la carte NoWave.
///
/// La bathymétrie raster est uniquement visuelle.
/// Les informations de profondeur exploitables seront ajoutées séparément
/// avec des courbes bathymétriques vectorielles.
class MarineMapController {
  static const String bathymetrySourceId = 'nowave-bathymetry';
  static const String bathymetryLayerId = 'nowave-bathymetry-raster';

  /// URL des tuiles bathymétriques.
  ///
  /// Elle reste extérieure au code pour pouvoir changer de fournisseur
  /// ou passer plus tard à nos propres tuiles sans modifier l'application.
  static const String _bathymetryTilesUrl = String.fromEnvironment(
    'BATHYMETRY_TILES_URL',
    defaultValue: '',
  );

  /// Bleu profond utilisé pour l'océan à l'échelle mondiale.
  /// Il reprend la teinte générale de la référence visuelle NoWave.
  static const String deepWaterColor = '#DEF2FB';

  Future<void> install(MapboxMap map) async {
    final style = map.style;

    // Vue globe lorsque le niveau de zoom le permet.
    await style.setProjection(StyleProjection(name: StyleProjectionName.globe));

    // Océan Mapbox Standard teinté dans notre bleu profond.
    // Cette couleur sert aussi de fond lorsqu'aucune donnée bathymétrique
    // détaillée n'est disponible.
    await style.setStyleImportConfigProperty(
      'basemap',
      'colorWater',
      deepWaterColor,
    );

    if (_bathymetryTilesUrl.trim().isEmpty) {
      debugPrint(
        'Bathymétrie visuelle désactivée : '
        'BATHYMETRY_TILES_URL absent.',
      );
      return;
    }

    // Source ajoutée une seule fois par chargement du style.
    if (!await style.styleSourceExists(bathymetrySourceId)) {
      await style.addSource(
        RasterSource(
          id: bathymetrySourceId,
          tiles: [_bathymetryTilesUrl],
          tileSize: 256,
          minzoom: 0,
          maxzoom: 14,
          volatile: true,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.25,
        ),
      );
    }

    // La bathymétrie reste sous les informations cartographiques,
    // les signalements NoWave et la position GPS.
    if (!await style.styleLayerExists(bathymetryLayerId)) {
      await style.addLayer(
        RasterLayer(
          id: bathymetryLayerId,
          sourceId: bathymetrySourceId,
          slot: LayerSlot.BOTTOM,
          rasterOpacity: 1.0,
          rasterFadeDuration: 150,
          rasterResampling: RasterResampling.LINEAR,
        ),
      );
    }
  }
}
