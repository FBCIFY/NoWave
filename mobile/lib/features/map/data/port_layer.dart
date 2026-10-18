import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import 'marine_tiles.dart';

/// Habillage NoWave des infrastructures portuaires.
///
/// Source : fusion NoWave des sources officielles et OSM Shortbread.
///
/// Hiérarchie visuelle :
/// - bassins : très discrets ;
/// - digues : visibles assez tôt ;
/// - épis : secondaires ;
/// - pontons : visibles seulement lorsqu'on s'approche du port.
///
/// Les bouées, sondes et noms de ports sont volontairement absents.
class PortLayer {
  static const String sourceId = 'nowave-osm-ports';

  static const String _dockLayerId = 'nowave-port-docks';
  static const String _pierPolygonLayerId = 'nowave-port-pier-polygons';

  static const String _breakwaterLayerId = 'nowave-port-breakwaters';
  static const String _groyneLayerId = 'nowave-port-groynes';
  static const String _pierLayerId = 'nowave-port-piers';

  static String tilesUrl({String apiBaseUrl = ApiConfig.baseUrl}) =>
      MarineTiles.template('port-infrastructure', apiBaseUrl: apiBaseUrl);
  static Future<void>? _installing;

  static Future<void> addTo(
    MapboxMap map, {
    String apiBaseUrl = ApiConfig.baseUrl,
  }) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        /* Le style peut avoir changé. */
      }
      return addTo(map, apiBaseUrl: apiBaseUrl);
    }
    final install = _install(map, apiBaseUrl);
    _installing = install;
    try {
      await install;
    } finally {
      _installing = null;
    }
  }

  static Future<void> _install(MapboxMap map, String apiBaseUrl) async {
    final style = map.style;

    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        VectorSource(
          id: sourceId,
          tiles: [tilesUrl(apiBaseUrl: apiBaseUrl)],
          minzoom: 10,
          maxzoom: 14,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.25,
          attribution: MarineTiles.attribution(apiBaseUrl: apiBaseUrl),
        ),
      );
    }

    // Eau intérieure des bassins.
    //
    // Elle doit seulement aider à comprendre la forme du port :
    // la bathymétrie reste visible dessous.
    if (!await style.styleLayerExists(_dockLayerId)) {
      await style.addLayer(
        FillLayer(
          id: _dockLayerId,
          sourceId: sourceId,
          sourceLayer: 'water_polygons',
          minZoom: 10,
          slot: LayerSlot.BOTTOM,
          filter: const [
            '==',
            ['get', 'kind'],
            'dock',
          ],
          fillColor: 0xFFB9E3F4,
          fillOpacity: 0.18,
          fillOutlineColor: 0xFF87B8CC,
        ),
      );
    }

    // Ouvrages cartographiés comme surfaces.
    //
    // Beaucoup plus clairs que dans la première version afin d'éviter
    // les masses sombres dans les grandes marinas.
    if (!await style.styleLayerExists(_pierPolygonLayerId)) {
      await style.addLayer(
        FillLayer(
          id: _pierPolygonLayerId,
          sourceId: sourceId,
          sourceLayer: 'pier_polygons',
          minZoom: 13,
          slot: LayerSlot.MIDDLE,
          fillColor: 0xFFDDE6EA,
          fillOpacity: 0.70,
          fillOutlineColor: 0xFF91A5B0,
        ),
      );
    }

    // Digues : élément principal pour lire l'entrée et la protection du port.
    if (!await style.styleLayerExists(_breakwaterLayerId)) {
      await style.addLayer(
        LineLayer(
          id: _breakwaterLayerId,
          sourceId: sourceId,
          sourceLayer: 'pier_lines',
          minZoom: 11.5,
          slot: LayerSlot.MIDDLE,
          filter: const [
            '==',
            ['get', 'kind'],
            'breakwater',
          ],
          lineColor: 0xFF607887,
          lineOpacity: 0.78,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidthExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            11.5,
            1.1,
            14,
            1.8,
            16,
            2.7,
            18,
            3.6,
          ],
        ),
      );
    }

    // Épis : utiles pour la lecture du littoral mais volontairement secondaires.
    if (!await style.styleLayerExists(_groyneLayerId)) {
      await style.addLayer(
        LineLayer(
          id: _groyneLayerId,
          sourceId: sourceId,
          sourceLayer: 'pier_lines',
          minZoom: 12.5,
          slot: LayerSlot.MIDDLE,
          filter: const [
            '==',
            ['get', 'kind'],
            'groyne',
          ],
          lineColor: 0xFF8296A1,
          lineOpacity: 0.55,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidthExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            12.5,
            0.45,
            14,
            0.70,
            16,
            1.0,
            18,
            1.3,
          ],
        ),
      );
    }

    // Pontons : ils ne doivent pas transformer une marina en "peigne noir"
    // lorsqu'on regarde encore la ville entière.
    if (!await style.styleLayerExists(_pierLayerId)) {
      await style.addLayer(
        LineLayer(
          id: _pierLayerId,
          sourceId: sourceId,
          sourceLayer: 'pier_lines',
          minZoom: 13,
          slot: LayerSlot.MIDDLE,
          filter: const [
            '==',
            ['get', 'kind'],
            'pier',
          ],
          lineColor: 0xFF748B99,
          lineOpacity: 0.68,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
          lineWidthExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            13,
            0.50,
            14,
            0.75,
            16,
            1.30,
            18,
            1.90,
          ],
        ),
      );
    }
  }
}
