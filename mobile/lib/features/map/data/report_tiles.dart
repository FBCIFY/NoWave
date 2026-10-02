import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import '../../reports/domain/manual_report.dart';
import '../../reports/presentation/report_category_style.dart';
import '../presentation/report_marker.dart';

/// Couche des signalements sur la carte. Les tuiles MVT viennent du backend
/// (`GET api/v1/map/tiles/{z}/{x}/{y}.mvt`), qui exige le token Firebase
/// comme les autres routes.
///
/// Jusqu'au zoom 8, le backend regroupe les signalements proches : un
/// regroupement porte `cluster` et `cluster_count`, sans `report_id` ni
/// `category`.
class ReportTiles {
  factory ReportTiles({
    required Future<String> Function() getIdToken,
    String apiBaseUrl = ApiConfig.baseUrl,
  }) => ReportTiles._(getIdToken, apiBaseUrl);

  ReportTiles._(this._getIdToken, this._apiBaseUrl);

  static const sourceId = 'nowave-reports';

  /// Un badge par signalement, à l'icône et à la couleur de sa catégorie.
  static const pointsLayerId = 'nowave-reports-points';

  /// Un rond par regroupement.
  static const clustersLayerId = 'nowave-reports-clusters';

  /// Nombre de signalements écrit sur chaque regroupement.
  static const clusterCountLayerId = 'nowave-reports-cluster-count';

  /// Nom de la couche à l'intérieur des tuiles, fixé par le backend.
  static const _sourceLayer = 'reports';

  /// Garde les couleurs vives quel que soit l'éclairage du style Mapbox
  /// Standard (aube, crépuscule, nuit).
  static const _fullBrightness = 1.0;

  static const _clusterColor = 0xFF172554;
  static const _white = 0xFFFFFFFF;

  /// Badge d'une catégorie inconnue de cette version de l'app : le
  /// signalement reste visible.
  static const _unknownMarkerId = 'nowave-report-unknown';
  static const _unknownMarkerIcon = Icons.place_outlined;
  static const _unknownMarkerColor = Color(0xFF64748B);

  static String _markerIdOf(ReportCategory category) =>
      'nowave-report-${category.apiValue}';

  /// Expression Mapbox qui choisit le badge selon `category`.
  @visibleForTesting
  static List<Object> markerImageExpression() => [
    'match',
    ['get', 'category'],
    for (final category in ReportCategory.values) ...[
      category.apiValue,
      _markerIdOf(category),
    ],
    _unknownMarkerId,
  ];

  /// `cluster` vaut `true` sur un regroupement, `false` sur un signalement.
  static const _isCluster = [
    '==',
    ['get', 'cluster'],
    true,
  ];
  static const _isReport = [
    '!=',
    ['get', 'cluster'],
    true,
  ];

  final Future<String> Function() _getIdToken;
  final String _apiBaseUrl;

  /// Badges en PNG, dessinés au premier affichage puis réutilisés à chaque
  /// chargement de style.
  Future<Map<String, Uint8List>>? _markers;

  /// Donne le token à Mapbox, pour les requêtes vers le backend seulement :
  /// le fond de carte, servi par Mapbox, ne doit pas le recevoir.
  Future<void> authorize(MapboxMap map) async {
    final token = await _getIdToken();
    await map.httpService.setCustomHeadersForHost(Uri.parse(_apiBaseUrl).host, {
      'Authorization': 'Bearer $token',
    });
  }

  /// Ajoute les badges, la source et les couches. Un changement de style les
  /// efface : à rappeler après chaque chargement de style.
  Future<void> addTo(MapboxMap map) async {
    await authorize(map);
    if (await map.style.styleSourceExists(sourceId)) return;

    final markers = await (_markers ??= _paintMarkers());
    final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
    for (final MapEntry(key: id, value: png) in markers.entries) {
      await map.style.addStyleImage(
        id,
        ReportMarker.pixelRatio,
        MbxImage(width: side, height: side, data: png),
        false,
        [],
        [],
        null,
      );
    }

    await map.style.addSource(
      VectorSource(
        id: sourceId,
        tiles: ['${_apiBaseUrl}api/v1/map/tiles/{z}/{x}/{y}.mvt'],
      ),
    );
    await map.style.addLayer(
      SymbolLayer(
        id: pointsLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        filter: _isReport,
        iconImageExpression: markerImageExpression(),
        // Tous les signalements restent visibles, même serrés : en masquer
        // un ferait disparaître un danger.
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconEmissiveStrength: _fullBrightness,
      ),
    );
    await map.style.addLayer(
      CircleLayer(
        id: clustersLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        filter: _isCluster,
        // Le rond grossit avec le nombre de signalements regroupés.
        circleRadiusExpression: [
          'step',
          ['get', 'cluster_count'],
          14,
          10,
          18,
          50,
          22,
        ],
        circleColor: _clusterColor,
        circleStrokeColor: _white,
        circleStrokeWidth: 2,
        circleEmissiveStrength: _fullBrightness,
      ),
    );
    await map.style.addLayer(
      SymbolLayer(
        id: clusterCountLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        filter: _isCluster,
        textFieldExpression: [
          'to-string',
          ['get', 'cluster_count'],
        ],
        textSize: 13,
        textColor: _white,
        // Le nombre reste affiché même s'il chevauche une étiquette du fond.
        textAllowOverlap: true,
        textIgnorePlacement: true,
        textEmissiveStrength: _fullBrightness,
      ),
    );
  }

  static Future<Map<String, Uint8List>> _paintMarkers() async => {
    for (final category in ReportCategory.values)
      _markerIdOf(category): await ReportMarker.paint(
        icon: category.icon,
        color: category.color,
      ),
    _unknownMarkerId: await ReportMarker.paint(
      icon: _unknownMarkerIcon,
      color: _unknownMarkerColor,
    ),
  };
}
