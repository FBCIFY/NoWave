import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import '../../reports/domain/manual_report.dart';
import '../presentation/report_marker.dart';

/// Couche des signalements sur la carte. Les tuiles MVT viennent du backend
/// (`GET api/v1/map/tiles/{z}/{x}/{y}.mvt`), qui exige le token Firebase
/// comme les autres routes.
///
/// Jusqu'au zoom 8, le backend regroupe les signalements proches : un
/// regroupement porte `cluster` et `cluster_count`, sans `report_id` ni
/// `category`. De loin, la carte montre donc une carte de chaleur plate,
/// sans chiffre, du violet au rouge selon le nombre de signalements ; de
/// près, un badge par signalement.
class ReportTiles {
  factory ReportTiles({
    required Future<String> Function() getIdToken,
    String apiBaseUrl = ApiConfig.baseUrl,
  }) => ReportTiles._(getIdToken, apiBaseUrl);

  ReportTiles._(this._getIdToken, this._apiBaseUrl);

  static const sourceId = 'nowave-reports';

  /// Un badge par signalement, à l'icône et à la couleur de sa catégorie.
  static const pointsLayerId = 'nowave-reports-points';

  /// Zone colorée, plus chaude là où les signalements sont nombreux.
  static const heatmapLayerId = 'nowave-reports-heatmap';

  /// Point invisible sur chaque zone, que le doigt peut toucher : Mapbox
  /// ne sait pas dire quelle zone d'une heatmap a été touchée.
  static const clusterTapLayerId = 'nowave-reports-cluster-tap';

  /// Nom de la couche à l'intérieur des tuiles, fixé par le backend.
  static const _sourceLayer = 'reports';

  /// Dernier zoom demandé au backend : au zoom 12, une tuile place déjà
  /// un badge à 2 m près ; au-delà, Mapbox agrandit celle-ci.
  static const _tilesMaxZoom = 12.0;

  /// Attente avant de demander les tuiles pendant un geste ou une
  /// animation, en secondes.
  static const _gestureTilesDelaySeconds = 0.5;

  /// Garde les couleurs vives quel que soit l'éclairage du style Mapbox
  /// Standard (aube, crépuscule, nuit).
  static const _fullBrightness = 1.0;

  /// Zoom à partir duquel les badges remplacent la zone colorée : le
  /// backend ne regroupe plus les signalements.
  static const badgesMinZoom = 9.0;

  /// Zoom où la zone colorée commence à s'effacer : elle est partie quand
  /// les badges arrivent. La zone ne va pas au-delà : sur
  /// les tuiles du zoom 9, chaque signalement chaufferait séparément et les
  /// voisins s'additionneraient jusqu'au rouge.
  static const _fadeStartZoom = 8.5;

  /// Zoom où les badges ont fini de grandir.
  static const _badgesFullZoom = 9.5;

  /// Taille des badges au début du fondu, avant de grandir jusqu'à 1.
  static const _badgeStartScale = 0.6;

  static const _white = 0xFFFFFFFF;

  /// Rayon du point touchable, en pixels ; la marge du doigt s'y ajoute.
  static const _clusterTapRadius = 16.0;

  /// Assez pour que Mapbox garde le point touchable, trop peu pour le voir :
  /// une couche à opacité nulle n'est pas dessinée et peut être ignorée au
  /// toucher.
  static const _invisibleOpacity = 0.01;

  /// Nombre de signalements d'une feature : 1 pour un signalement seul.
  static const _count = [
    'coalesce',
    ['get', 'cluster_count'],
    1,
  ];

  /// Rayon de la zone colorée en pixels, aux zooms 0, 6 et 9 : assez
  /// large pour se lire comme une zone et pas comme un point. Le rayon reste
  /// fixe, comme sur Snap Map.
  @visibleForTesting
  static const heatmapRadiusExpression = [
    'interpolate',
    ['linear'],
    ['zoom'],
    0.0,
    25.0,
    6.0,
    50.0,
    badgesMinZoom,
    80.0,
  ];

  /// Couleur selon la densité, comme Snap Map : violet, bleu, vert, jaune,
  /// orange, rouge, et un cœur rouge foncé sur les zones très chargées. Le
  /// bord est presque transparent et le centre opaque, pour que la zone se
  /// fonde dans la carte.
  @visibleForTesting
  static const heatmapColorExpression = [
    'interpolate',
    ['linear'],
    ['heatmap-density'],
    0,
    'rgba(139, 92, 246, 0)',
    0.05,
    'rgba(139, 92, 246, 0.2)',
    0.15,
    'rgba(139, 92, 246, 0.4)',
    0.3,
    'rgba(59, 130, 246, 0.55)',
    0.45,
    'rgba(34, 197, 94, 0.7)',
    0.6,
    'rgba(250, 204, 21, 0.8)',
    0.75,
    'rgba(249, 115, 22, 0.9)',
    0.9,
    'rgb(220, 38, 38)',
    1,
    'rgb(110, 20, 20)',
  ];

  /// Valeur qui suit le zoom : [start] au zoom [from], [end] au zoom [to],
  /// et entre les deux une transition régulière.
  static List<Object> _zoomRamp(
    double from,
    double start,
    double to,
    double end,
  ) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    from,
    start,
    to,
    end,
  ];

  /// Badge d'une catégorie inconnue de cette version de l'app : le
  /// signalement reste visible.
  static const _unknownMarkerId = 'nowave-report-unknown';
  static const _unknownMarkerIcon = Icons.place_outlined;
  static const _unknownMarkerColor = Color(0xFF64748B);

  /// Un 403 sur les tuiles indique un refus d'accès. Comme l'erreur
  /// Mapbox n'expose pas le code métier NoWave, le profil doit ensuite
  /// être revalidé avant de conclure que le compte est suspendu.
  static bool isForbidden(String message) =>
      RegExp(r'status code 403\b').hasMatch(message);

  static String _markerIdOf(ReportCategory category) =>
      ReportMarker.imageId(category);

  /// Taille partagée par les badges ordinaires et la sélection.
  /// [scale] grossit le badge du signalement sélectionné.
  static List<Object> markerSizeExpression({double scale = 1}) => _zoomRamp(
    badgesMinZoom,
    _badgeStartScale * scale,
    _badgesFullZoom,
    scale,
  );

  /// Expression partagée par les badges ordinaires et la sélection.
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
  static const _isReport = [
    '!=',
    ['get', 'cluster'],
    true,
  ];

  final Future<String> Function() _getIdToken;
  final String _apiBaseUrl;

  /// Badges PNG, dessinés au premier affichage puis réutilisés à chaque
  /// chargement de style.
  Future<Map<String, Uint8List>>? _markers;

  /// Donne le token à Mapbox, pour les requêtes vers le backend seulement :
  /// le fond de carte, servi par Mapbox, ne doit pas le recevoir.
  Future<void> authorize(MapboxMap map) async {
    final backend = ApiConfig.resolve('', baseUrl: _apiBaseUrl);
    final token = await _getIdToken();
    await map.httpService.setCustomHeadersForHost(backend.host, {
      'Authorization': 'Bearer $token',
    });
  }

  /// Ajoute les badges, la source et les couches. Un changement de style les
  /// efface : à rappeler après chaque chargement de style.
  ///
  /// Sans danger si on le rappelle : ce qui existe déjà n'est pas recréé,
  /// et une installation interrompue reprend où elle s'était arrêtée.
  Future<void> addTo(MapboxMap map) async {
    await authorize(map);
    final style = map.style;

    final markers = await (_markers ??= _paintMarkers());
    final side = (ReportMarker.size * ReportMarker.pixelRatio).round();
    for (final MapEntry(key: id, value: png) in markers.entries) {
      await style.addStyleImage(
        id,
        ReportMarker.pixelRatio,
        MbxImage(width: side, height: side, data: png),
        false,
        [],
        [],
        null,
      );
    }

    // Le backend sert les tuiles avec `max-age=15` : Mapbox redemande
    // lui-même celles qui sont visibles une fois expirées, et les remplace
    // sans effacer les badges. Les signalements publiés, expirés ou retirés
    // apparaissent ou disparaissent donc en 15 s environ. En arrière-plan,
    // la carte coupe le réseau de Mapbox pour l'en empêcher.
    //
    // Le proxy donne aux tuiles un budget séparé de 30 requêtes/s (rafale
    // de 50) et limite toujours chaque IP à 30 connexions. On garde le
    // nombre de tuiles demandé bas tant que la recette de zoom n'a pas
    // mesuré la marge disponible :
    // aucune au-delà du zoom 12, agrandi ensuite par Mapbox ; pas de
    // préchargement des zooms inférieurs ; les requêtes réseau des tuiles
    // transitoires sont retardées pendant les gestes et animations.
    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        VectorSource(
          id: sourceId,
          tiles: [
            ApiConfig.tileTemplate(
              'tiles',
              extension: 'mvt',
              baseUrl: _apiBaseUrl,
            ),
          ],
          maxzoom: _tilesMaxZoom,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: _gestureTilesDelaySeconds,
        ),
      );
    }
    // Chaque couche a sa plage de zoom : même quand Mapbox garde une
    // tuile d'un autre zoom le temps d'en charger une nouvelle, on ne voit
    // jamais la zone et les badges en même temps.
    await _addLayerOnce(
      style,
      HeatmapLayer(
        id: heatmapLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        maxZoom: badgesMinZoom,
        // Sous les étiquettes du fond de carte, qui restent lisibles.
        slot: LayerSlot.MIDDLE,
        // Au cœur d'une tache, Mapbox compte environ 0,4 par unité de
        // poids : un signalement seul reste violet ou bleu, une dizaine
        // passe au jaune, une trentaine atteint le rouge foncé. Au dézoom,
        // les taches voisines s'additionnent et changent de couleur.
        heatmapWeightExpression: [
          'interpolate',
          ['linear'],
          _count,
          1,
          0.5,
          10,
          1.5,
          30,
          2.5,
        ],
        heatmapRadiusExpression: heatmapRadiusExpression,
        heatmapColorExpression: heatmapColorExpression,
        heatmapOpacityExpression: _zoomRamp(
          _fadeStartZoom,
          1,
          badgesMinZoom,
          0,
        ),
      ),
    );
    await _addLayerOnce(
      style,
      CircleLayer(
        id: clusterTapLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        maxZoom: badgesMinZoom,
        slot: LayerSlot.MIDDLE,
        circleRadius: _clusterTapRadius,
        circleColor: _white,
        circleOpacity: _invisibleOpacity,
      ),
    );
    await _addLayerOnce(
      style,
      SymbolLayer(
        id: pointsLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        minZoom: badgesMinZoom,
        // Au-dessus du fond de carte, mais sous la flèche de position,
        // ajoutée sans emplacement par Mapbox.
        slot: LayerSlot.TOP,
        filter: _isReport,
        iconImageExpression: markerImageExpression(),
        // À 9, la zone colorée est déjà masquée : le badge doit être visible.
        iconOpacity: 1,
        iconSizeExpression: markerSizeExpression(),
        // Tous les signalements restent visibles, même serrés : en masquer
        // un ferait disparaître un danger.
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconEmissiveStrength: _fullBrightness,
      ),
    );
  }

  static Future<void> _addLayerOnce(StyleManager style, Layer layer) async {
    if (await style.styleLayerExists(layer.id)) return;
    await style.addLayer(layer);
  }

  static Future<Map<String, Uint8List>> _paintMarkers() async => {
    for (final category in ReportCategory.values)
      _markerIdOf(category): await ReportMarker.paintCategory(category),
    _unknownMarkerId: await ReportMarker.paint(
      icon: _unknownMarkerIcon,
      color: _unknownMarkerColor,
    ),
  };
}
