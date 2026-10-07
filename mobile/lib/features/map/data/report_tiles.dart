import 'dart:async';
import 'dart:math' as math;
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
/// `category`. De loin, la carte montre donc une zone colorée selon le
/// nombre de signalements, avec ce nombre écrit dessus ; de près, un badge
/// par signalement.
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

  /// Nombre de signalements écrit sur chaque zone.
  static const countLayerId = 'nowave-reports-count';

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
  static const _badgesMinZoom = 9.0;

  /// Zoom où la zone colorée et son nombre commencent à s'effacer : ils
  /// sont partis quand les badges arrivent. La zone ne va pas au-delà : sur
  /// les tuiles du zoom 9, chaque signalement chaufferait séparément et les
  /// voisins s'additionneraient jusqu'au rouge.
  static const _fadeStartZoom = 8.5;

  /// Zoom où les badges ont fini d'apparaître, en fondu et en grandissant.
  static const _badgesFullZoom = 9.5;

  /// Taille des badges au début du fondu, avant de grandir jusqu'à 1.
  static const _badgeStartScale = 0.6;

  /// Bleu marine du nombre, détouré de blanc : lisible sur le jaune comme
  /// sur le rouge.
  static const _countColor = 0xFF172554;
  static const _white = 0xFFFFFFFF;

  /// Nombre de signalements d'une feature : 1 pour un signalement seul.
  static const _count = [
    'coalesce',
    ['get', 'cluster_count'],
    1,
  ];

  /// Rayon de la zone colorée en pixels, aux zooms 0, 6 et 9 : assez
  /// large pour se lire comme une zone et pas comme un point.
  static const _heatmapRadii = [
    (0.0, 25.0),
    (6.0, 50.0),
    (_badgesMinZoom, 80.0),
  ];

  /// Durée d'un battement complet de la zone colorée.
  static const _pulsePeriod = Duration(seconds: 2);

  /// Agrandissement maximal du rayon au milieu d'un battement : +25 %.
  static const _pulseAmplitude = 0.25;

  /// Intervalle entre deux mises à jour du rayon, soit 20 images par
  /// seconde : fluide sans surcharger la carte.
  static const _pulseFrame = Duration(milliseconds: 50);

  /// Rayon de la zone colorée selon le zoom, multiplié par [scale] pendant
  /// le battement.
  @visibleForTesting
  static List<Object> heatmapRadiusExpression([double scale = 1]) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    for (final (zoom, radius) in _heatmapRadii) ...[zoom, radius * scale],
  ];

  /// Facteur du rayon après [elapsed] : part de 1, monte à 1,25 à
  /// mi-battement puis redescend, sans à-coup.
  @visibleForTesting
  static double pulseScale(Duration elapsed) {
    final phase = elapsed.inMicroseconds / _pulsePeriod.inMicroseconds;
    return 1 + _pulseAmplitude * (1 - math.cos(2 * math.pi * phase)) / 2;
  }

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

  /// Battement en cours ; null quand la zone colorée est fixe.
  Timer? _pulseTimer;

  /// Temps écoulé depuis le début du battement.
  final _pulseClock = Stopwatch();

  /// Mise à jour du rayon encore en cours : on saute l'image suivante
  /// plutôt que d'empiler les appels.
  bool _pulseUpdating = false;

  /// Fait battre la zone colorée tant qu'elle est visible, c'est-à-dire
  /// sous le zoom des badges, et que l'animation est permise.
  void updatePulse(
    MapboxMap map, {
    required double zoom,
    required bool enabled,
  }) {
    if (enabled && zoom < _badgesMinZoom) {
      _startPulse(map);
    } else {
      stopPulse();
    }
  }

  /// Arrête le battement ; à appeler quand l'app passe en arrière-plan ou
  /// que la carte disparaît.
  void stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulseClock
      ..stop()
      ..reset();
  }

  /// Lance le battement s'il ne tourne pas déjà.
  void _startPulse(MapboxMap map) {
    if (_pulseTimer != null) return;
    _pulseClock.start();
    _pulseTimer = Timer.periodic(_pulseFrame, (_) => _pulseStep(map));
  }

  /// Une image du battement : applique le rayon du moment.
  Future<void> _pulseStep(MapboxMap map) async {
    if (_pulseUpdating) return;
    _pulseUpdating = true;
    try {
      await map.style.setStyleLayerProperty(
        heatmapLayerId,
        'heatmap-radius',
        heatmapRadiusExpression(pulseScale(_pulseClock.elapsed)),
      );
    } catch (_) {
      // Couche absente le temps d'un rechargement du style : l'image
      // suivante réessaiera.
    } finally {
      _pulseUpdating = false;
    }
  }

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
    // apparaissent ou disparaissent donc en 15 s environ.
    //
    // Le serveur limite chaque appareil à 10 requêtes/s (pointes à 30) et
    // 30 connexions ; au-delà, il répond 429 ou 503 et les badges tardent
    // d'une à deux minutes. On demande donc le moins de tuiles possible :
    // aucune au-delà du zoom 12, agrandi ensuite par Mapbox ; pas de
    // préchargement des zooms inférieurs ; et rien pendant un geste, où les
    // zooms traversés ne restent pas affichés.
    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        VectorSource(
          id: sourceId,
          tiles: ['${_apiBaseUrl}api/v1/map/tiles/{z}/{x}/{y}.mvt'],
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
        maxZoom: _badgesMinZoom,
        // Sous les étiquettes du fond de carte, qui restent lisibles.
        slot: LayerSlot.MIDDLE,
        // Un signalement seul chauffe à moitié, dix ou plus à fond.
        heatmapWeightExpression: [
          'interpolate',
          ['linear'],
          _count,
          1,
          0.5,
          10,
          1,
        ],
        heatmapRadiusExpression: heatmapRadiusExpression(),
        // Du jaune au rouge, sans vert : peu de signalements ne veut pas
        // dire que la zone est sûre.
        heatmapColorExpression: [
          'interpolate',
          ['linear'],
          ['heatmap-density'],
          0,
          'rgba(250, 204, 21, 0)',
          0.15,
          'rgba(250, 204, 21, 0.55)',
          0.4,
          'rgb(250, 204, 21)',
          0.7,
          'rgb(249, 115, 22)',
          1,
          'rgb(220, 38, 38)',
        ],
        heatmapOpacityExpression: _zoomRamp(
          _fadeStartZoom,
          0.85,
          _badgesMinZoom,
          0,
        ),
      ),
    );
    await _addLayerOnce(
      style,
      SymbolLayer(
        id: countLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        maxZoom: _badgesMinZoom,
        textFieldExpression: ['to-string', _count],
        textSize: 14,
        textColor: _countColor,
        textHaloColor: _white,
        textHaloWidth: 1.5,
        textOpacityExpression: _zoomRamp(_fadeStartZoom, 1, _badgesMinZoom, 0),
        // Deux nombres qui se chevauchent seraient illisibles : le second
        // s'efface, la zone colorée montre quand même ses signalements. Le
        // fond de carte, lui, n'est pas masqué.
        textIgnorePlacement: true,
        textEmissiveStrength: _fullBrightness,
      ),
    );
    await _addLayerOnce(
      style,
      SymbolLayer(
        id: pointsLayerId,
        sourceId: sourceId,
        sourceLayer: _sourceLayer,
        minZoom: _badgesMinZoom,
        filter: _isReport,
        iconImageExpression: markerImageExpression(),
        iconOpacityExpression: _zoomRamp(_badgesMinZoom, 0, _badgesFullZoom, 1),
        iconSizeExpression: _zoomRamp(
          _badgesMinZoom,
          _badgeStartScale,
          _badgesFullZoom,
          1,
        ),
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
