import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';

/// Couche des signalements sur la carte. Les tuiles MVT viennent du backend
/// (`GET api/v1/map/tiles/{z}/{x}/{y}.mvt`), qui exige le token Firebase
/// comme les autres routes.
class ReportTiles {
  factory ReportTiles({
    required Future<String> Function() getIdToken,
    String apiBaseUrl = ApiConfig.baseUrl,
  }) => ReportTiles._(getIdToken, apiBaseUrl);

  ReportTiles._(this._getIdToken, this._apiBaseUrl);

  static const sourceId = 'nowave-reports';
  static const layerId = 'nowave-reports-points';

  /// Nom de la couche à l'intérieur des tuiles, fixé par le backend.
  static const _sourceLayer = 'reports';

  final Future<String> Function() _getIdToken;
  final String _apiBaseUrl;

  /// Donne le token à Mapbox, pour les requêtes vers le backend seulement :
  /// le fond de carte, servi par Mapbox, ne doit pas le recevoir.
  Future<void> authorize(MapboxMap map) async {
    final token = await _getIdToken();
    await map.httpService.setCustomHeadersForHost(Uri.parse(_apiBaseUrl).host, {
      'Authorization': 'Bearer $token',
    });
  }

  /// Ajoute la source et la couche. Un changement de style les efface :
  /// à rappeler après chaque chargement de style.
  Future<void> addTo(MapboxMap map) async {
    await authorize(map);
    if (await map.style.styleSourceExists(sourceId)) return;

    await map.style.addSource(
      VectorSource(
        id: sourceId,
        tiles: ['${_apiBaseUrl}api/v1/map/tiles/{z}/{x}/{y}.mvt'],
      ),
    );
    // Rond provisoire, le temps de vérifier que les tuiles arrivent.
    await map.style.addLayer(
      CircleLayer(
        id: layerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        circleRadius: 8,
        circleColor: 0xFFE8502A,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2,
      ),
    );
  }
}
