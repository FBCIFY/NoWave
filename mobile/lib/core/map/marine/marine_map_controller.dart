import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../api/api_config.dart';
import 'marine_palette.dart';
import 'marine_zoom.dart';

/// Habillage marin commun de la carte NoWave.
///
/// La bathymétrie raster est uniquement visuelle.
/// Les informations de profondeur exploitables seront ajoutées séparément
/// avec des courbes bathymétriques vectorielles.
class MarineMapController {
  MarineMapController({String? bathymetryTilesUrl, String? apiBaseUrl})
    : _tilesUrl = bathymetryTilesUrl,
      apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl;

  final String? _tilesUrl;
  final String apiBaseUrl;
  static const String bathymetrySourceId = 'nowave-bathymetry';
  static const String bathymetryLayerId = 'nowave-bathymetry-raster';

  /// Fond marin sans données, dans la même palette que le raster.
  static const String deepWaterColor = MarinePalette.water;

  Future<void> install(MapboxMap map) async {
    final tilesUrl =
        _tilesUrl ??
        ApiConfig.tileTemplate(
          'bathymetry',
          extension: 'png',
          baseUrl: apiBaseUrl,
        );
    final style = map.style;

    // Vue globe lorsque le niveau de zoom le permet.
    await style.setProjection(StyleProjection(name: StyleProjectionName.globe));

    // Les propriétés individuelles préservent les réglages de visibilité
    // des noms de lieux pilotés par GlobePresentation selon le zoom.
    for (final setting in MarinePalette.basemapConfig.entries) {
      await style.setStyleImportConfigProperty(
        'basemap',
        setting.key,
        setting.value,
      );
    }

    // Une injection vide permet toujours de désactiver le raster dans un test.
    if (tilesUrl.trim().isEmpty) return;

    // Source ajoutée une seule fois par chargement du style.
    if (!await style.styleSourceExists(bathymetrySourceId)) {
      await style.addSource(
        RasterSource(
          id: bathymetrySourceId,
          // Versioned palette separates cached pixels without purging caches.
          tiles: [
            ApiConfig.withQueryParameters(tilesUrl, {'v': 'marine-palette-3'}),
          ],
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
          // Preserve the NW-220 raster slot and opacity from Z5.
          slot: LayerSlot.MIDDLE,
          minZoom: MarineZoom.raster,
          rasterOpacity: 1,
          rasterFadeDuration: 150,
          rasterResampling: RasterResampling.LINEAR,
          rasterContrast: 0,
          rasterSaturation: 0,
        ),
      );
    }
  }
}
