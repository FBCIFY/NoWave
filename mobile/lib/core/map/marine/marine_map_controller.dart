import 'dart:convert';

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
  MarineMapController({
    String? bathymetryTilesUrl,
    String? globalSeafloorTilesUrl,
    String? apiBaseUrl,
  }) : _tilesUrl = bathymetryTilesUrl,
       _globalTilesUrl = globalSeafloorTilesUrl,
       apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl;

  final String? _tilesUrl;
  final String? _globalTilesUrl;
  final String apiBaseUrl;
  static const String bathymetrySourceId = 'nowave-bathymetry';
  static const String bathymetryLayerId = 'nowave-bathymetry-raster';
  static const String globalSourceId = 'nowave-global-seafloor';
  static const String globalLayerId = 'nowave-global-seafloor-raster';

  /// Published mean_multicolour envelope, clipped to Web Mercator latitude.
  /// Native source bounds prevent requests for wholly external XYZ tiles.
  static const emodnetRasterBounds = [-73.125, 5.625, 45.0, 85.051129];

  /// Fond marin sans données, dans la même palette que le raster.
  static const String deepWaterColor = MarinePalette.water;

  String get _sourceDetails => apiBaseUrl.trim().isEmpty
      ? ''
      : ' · <a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(ApiConfig.endpoint('api/v1/map/marine-sources', baseUrl: apiBaseUrl))}">'
            'Sources et limites des données NoWave</a>';

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

    // This entire low-zoom pyramid is pre-rendered and served by Nginx.
    // Parent tiles arrive first; regional WMS/OSM work cannot queue this base.
    final globalUrl =
        _globalTilesUrl ??
        ApiConfig.tileTemplate(
          'seafloor/gebco-2026-v2',
          extension: 'webp',
          baseUrl: apiBaseUrl,
        );
    if (globalUrl.trim().isNotEmpty) {
      if (!await style.styleSourceExists(globalSourceId)) {
        await style.addSource(
          RasterSource(
            id: globalSourceId,
            tiles: [globalUrl],
            tileSize: 256,
            minzoom: 0,
            maxzoom: 6,
            attribution:
                '<a href="https://doi.org/10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa">'
                'GEBCO 2026 — vue d’ensemble mondiale, couleurs NoWave. '
                'Usage visuel, pas pour la navigation.</a>$_sourceDetails',
            volatile: false,
            prefetchZoomDelta: 4,
            tileNetworkRequestsDelay: 0,
          ),
        );
      }
      if (!await style.styleLayerExists(globalLayerId)) {
        await style.addLayer(
          RasterLayer(
            id: globalLayerId,
            sourceId: globalSourceId,
            slot: LayerSlot.MIDDLE,
            rasterOpacity: 1,
            rasterFadeDuration: 100,
            rasterResampling: RasterResampling.LINEAR,
          ),
        );
      }
    }

    // Source ajoutée une seule fois par chargement du style.
    if (!await style.styleSourceExists(bathymetrySourceId)) {
      await style.addSource(
        RasterSource(
          id: bathymetrySourceId,
          // Versioned palette separates cached pixels without purging caches.
          tiles: [
            ApiConfig.withQueryParameters(tilesUrl, {'v': 'marine-visual-7'}),
          ],
          tileSize: 256,
          minzoom: 5,
          maxzoom: 14,
          // Provider-advertised coverage: avoid blank requests elsewhere.
          bounds: emodnetRasterBounds,
          attribution:
              '<a href="https://emodnet.ec.europa.eu/en/bathymetry">'
              'Couleurs interpolées localement pour l’affichage, sans mesure ajoutée. '
              'Fond mondial GEBCO sous les détails régionaux</a>$_sourceDetails',
          // The versioned URL keeps old coastal renders separate. Reuse valid
          // public tiles on disk when returning to a place or reopening the app.
          volatile: false,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.6,
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
