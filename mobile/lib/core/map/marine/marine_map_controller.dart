import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../api/api_config.dart';
import 'marine_palette.dart';

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

  /// Fond marin accordé aux zones côtières claires du raster.
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
          // Separate clipped coast tiles from the previous unmasked cache.
          tiles: [
            ApiConfig.withQueryParameters(tilesUrl, {'v': 'coast-feather-2'}),
          ],
          tileSize: 256,
          minzoom: 0,
          maxzoom: 14,
          // The versioned URL keeps old coastal renders separate. Reuse valid
          // public tiles on disk when returning to a place or reopening the app.
          volatile: false,
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
          minZoom: 4,
          // L'emprise régionale EMODnet ne doit pas former un rectangle
          // contrasté sur le globe. Les détails apparaissent progressivement.
          rasterOpacityExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            4,
            0.0,
            7,
            1.0,
          ],
          rasterFadeDuration: 150,
          rasterResampling: RasterResampling.LINEAR,
          rasterContrast: .08,
          rasterSaturation: .08,
        ),
      );
    }
  }
}
