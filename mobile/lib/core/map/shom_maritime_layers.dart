import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Couches maritimes distantes utilisées par NoWave sur la façade
/// méditerranéenne française.
///
/// Les images sont servies directement par le WMTS public du Shom. Aucune
/// donnée cartographique Shom n'est embarquée dans l'application et aucune
/// base MBTiles/PBF locale n'est nécessaire.
class ShomMaritimeLayers {
  static const String wmtsEndpoint =
      'https://services.data.shom.fr/INSPIRE/wmts';
  static const String wfsEndpoint = 'https://services.data.shom.fr/INSPIRE/wfs';

  static const String bathymetryWmtsLayerId =
      'MNT_MED100m_GDL_CA_HOMONIM_PBMA_3857_WMTS';
  static const String regulationWmtsLayerId =
      'REGLEMENTATION_NAVIGATION_PYR_PNG_3857_WMTS';
  static const String harbourWmtsLayerId =
      'INFORMATIONS_PORTUAIRES_PYR_PNG_3857_WMTS';
  static const String marineNamesWmtsLayerId = 'TOPONYMIE_PYR_PNG_3857_WMTS';
  static const String buoyageWmtsLayerId = 'BALISAGE_PYR_PNG_3857_WMTS';
  static const String wrecksWmtsLayerId = 'EPAVES_PYR-PNG_WLD_3857_WMTS';

  /// Épaves et obstructions est préparé mais désactivé par défaut car ce
  /// produit Shom est diffusé sous CC BY-SA 4.0, contrairement aux couches
  /// actives ci-dessous. Son activation doit être décidée avec l'attribution
  /// et les obligations de licence correspondantes.
  static const bool wrecksEnabledByDefault = false;

  static const List<String> activeWmtsLayerIds = [
    bathymetryWmtsLayerId,
    regulationWmtsLayerId,
    harbourWmtsLayerId,
    marineNamesWmtsLayerId,
    buoyageWmtsLayerId,
  ];

  static const List<String> allWmtsLayerIds = [
    ...activeWmtsLayerIds,
    wrecksWmtsLayerId,
  ];

  static const String bathymetrySourceId = 'shom-bathymetry';
  static const String regulationSourceId = 'shom-regulation';
  static const String harbourSourceId = 'shom-harbours';
  static const String marineNamesSourceId = 'shom-marine-names';
  static const String buoyageSourceId = 'shom-buoyage';
  static const String wrecksSourceId = 'shom-wrecks';

  static const Set<String> sourceIds = {
    bathymetrySourceId,
    regulationSourceId,
    harbourSourceId,
    marineNamesSourceId,
    buoyageSourceId,
    wrecksSourceId,
  };

  /// Le maxzoom Mapbox est exclusif. 6.01 conserve donc les pays pendant le
  /// zoom 6 tout en faisant apparaître les villes juste après.
  static const double countryMaxZoom = 6.01;
  static const double cityMinZoom = 6.01;
  static const double cityMaxZoom = 12.0;

  static const String _placesSourceId = 'nowave-place-labels';
  static const String _countryLabelsLayerId = 'nowave-country-labels';
  static const String _cityLabelsLayerId = 'nowave-city-labels';
  static const String _placesSourceUrl = 'mapbox://mapbox.mapbox-streets-v8';

  /// Ancienne emprise France Méditerranée continentale du projet NoWave.
  /// Limiter les sources évite de demander au Shom des tuiles hors zone.
  static const List<double?> _franceMedBounds = [2.40, 41.85, 8.30, 44.45];

  static const String _shomOpenAttribution =
      '© Shom - data.shom.fr - Licence Ouverte 2.0';
  static const String _shomWrecksAttribution =
      '© Shom - data.shom.fr - CC BY-SA 4.0';

  static bool isSourceId(String? sourceId) =>
      sourceId != null && sourceIds.contains(sourceId);

  /// URL KVP WMTS compatible avec les placeholders XYZ compris par Mapbox.
  /// Le Shom publie ce service en Web Mercator EPSG:3857.
  static String tileUrl(String wmtsLayerId) =>
      '$wmtsEndpoint?service=WMTS&request=GetTile&version=1.0.0'
      '&layer=$wmtsLayerId&style=normal&tilematrixset=3857'
      '&format=image%2Fpng&TileMatrix={z}&TileCol={x}&TileRow={y}';

  /// Installe le style maritime NoWave sur le style Mapbox Standard courant.
  /// Sans danger après un rechargement du style : chaque source et couche est
  /// recréée seulement si elle n'existe pas déjà.
  static Future<void> addTo(
    MapboxMap map, {
    bool includeWrecks = wrecksEnabledByDefault,
  }) async {
    await _installPlaceLabels(map);

    final layers = <_ShomRasterSpec>[
      const _ShomRasterSpec(
        sourceId: bathymetrySourceId,
        layerId: 'shom-bathymetry-layer',
        wmtsLayerId: bathymetryWmtsLayerId,
        minZoom: 5,
        maxZoom: 20,
        opacity: 0.72,
        slot: LayerSlot.BOTTOM,
      ),
      const _ShomRasterSpec(
        sourceId: regulationSourceId,
        layerId: 'shom-regulation-layer',
        wmtsLayerId: regulationWmtsLayerId,
        minZoom: 7,
        maxZoom: 20,
        opacity: 0.82,
        slot: LayerSlot.MIDDLE,
      ),
      const _ShomRasterSpec(
        sourceId: harbourSourceId,
        layerId: 'shom-harbours-layer',
        wmtsLayerId: harbourWmtsLayerId,
        minZoom: 8,
        maxZoom: 20,
        opacity: 0.95,
        slot: LayerSlot.MIDDLE,
      ),
      const _ShomRasterSpec(
        sourceId: marineNamesSourceId,
        layerId: 'shom-marine-names-layer',
        wmtsLayerId: marineNamesWmtsLayerId,
        minZoom: 7,
        maxZoom: 20,
        opacity: 0.94,
        slot: LayerSlot.MIDDLE,
      ),
      const _ShomRasterSpec(
        sourceId: buoyageSourceId,
        layerId: 'shom-buoyage-layer',
        wmtsLayerId: buoyageWmtsLayerId,
        minZoom: 8,
        maxZoom: 20,
        opacity: 1,
        slot: LayerSlot.MIDDLE,
      ),
      if (includeWrecks)
        const _ShomRasterSpec(
          sourceId: wrecksSourceId,
          layerId: 'shom-wrecks-layer',
          wmtsLayerId: wrecksWmtsLayerId,
          minZoom: 9,
          maxZoom: 20,
          opacity: 1,
          slot: LayerSlot.MIDDLE,
          attribution: _shomWrecksAttribution,
        ),
    ];

    for (final layer in layers) {
      await _addRasterLayer(map, layer);
    }
  }

  static Future<void> _installPlaceLabels(MapboxMap map) async {
    final style = map.style;

    // Mapbox Standard garderait sinon ses propres pays et villes en plus des
    // règles NoWave ci-dessous.
    await style.setStyleImportConfigProperty(
      'basemap',
      'showPlaceLabels',
      false,
    );

    if (!await style.styleSourceExists(_placesSourceId)) {
      await style.addSource(
        VectorSource(
          id: _placesSourceId,
          url: _placesSourceUrl,
          volatile: true,
          attribution: '© Mapbox © OpenStreetMap',
        ),
      );
    }

    if (!await style.styleLayerExists(_countryLabelsLayerId)) {
      await style.addLayer(
        SymbolLayer(
          id: _countryLabelsLayerId,
          sourceId: _placesSourceId,
          sourceLayer: 'place_label',
          minZoom: 0,
          maxZoom: countryMaxZoom,
          slot: LayerSlot.TOP,
          filter: const [
            '==',
            ['get', 'class'],
            'country',
          ],
          textFieldExpression: const [
            'coalesce',
            ['get', 'name_fr'],
            ['get', 'name'],
          ],
          textSizeExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            0,
            11,
            6,
            17,
          ],
          textColor: 0xFF243243,
          textHaloColor: 0xFFF6F8FA,
          textHaloWidth: 1.5,
          textAllowOverlap: false,
          textIgnorePlacement: false,
          textEmissiveStrength: 1,
        ),
      );
    }

    if (!await style.styleLayerExists(_cityLabelsLayerId)) {
      await style.addLayer(
        SymbolLayer(
          id: _cityLabelsLayerId,
          sourceId: _placesSourceId,
          sourceLayer: 'place_label',
          minZoom: cityMinZoom,
          maxZoom: cityMaxZoom,
          slot: LayerSlot.TOP,
          filter: const [
            'in',
            ['get', 'type'],
            [
              'literal',
              ['city', 'town'],
            ],
          ],
          textFieldExpression: const [
            'coalesce',
            ['get', 'name_fr'],
            ['get', 'name'],
          ],
          textSizeExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            6.01,
            12,
            11.99,
            16,
          ],
          textColor: 0xFF243243,
          textHaloColor: 0xFFF6F8FA,
          textHaloWidth: 1.25,
          textAllowOverlap: false,
          textIgnorePlacement: false,
          textEmissiveStrength: 1,
        ),
      );
    }
  }

  static Future<void> _addRasterLayer(
    MapboxMap map,
    _ShomRasterSpec spec,
  ) async {
    final style = map.style;

    if (!await style.styleSourceExists(spec.sourceId)) {
      await style.addSource(
        RasterSource(
          id: spec.sourceId,
          tiles: [tileUrl(spec.wmtsLayerId)],
          bounds: _franceMedBounds,
          minzoom: spec.minZoom,
          maxzoom: spec.maxZoom,
          tileSize: 256,
          volatile: true,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.35,
          attribution: spec.attribution ?? _shomOpenAttribution,
        ),
      );
    }

    if (!await style.styleLayerExists(spec.layerId)) {
      await style.addLayer(
        RasterLayer(
          id: spec.layerId,
          sourceId: spec.sourceId,
          minZoom: spec.minZoom,
          maxZoom: spec.maxZoom,
          slot: spec.slot,
          rasterOpacity: spec.opacity,
          rasterFadeDuration: 150,
          rasterEmissiveStrength: 1,
        ),
      );
    }
  }
}

class _ShomRasterSpec {
  const _ShomRasterSpec({
    required this.sourceId,
    required this.layerId,
    required this.wmtsLayerId,
    required this.minZoom,
    required this.maxZoom,
    required this.opacity,
    required this.slot,
    this.attribution,
  });

  final String sourceId;
  final String layerId;
  final String wmtsLayerId;
  final double minZoom;
  final double maxZoom;
  final double opacity;
  final String slot;
  final String? attribution;
}
