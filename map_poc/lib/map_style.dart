import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads the style's provenance before rendering any geographic information.
class MapStyle {
  const MapStyle(
    this.json,
    this.isDemo,
    this.longitude,
    this.latitude,
    this.zoom, {
    this.reliefLabel = 'non renseigné',
    this.isReliefPreview = false,
    this.isCassisReal = false,
  });

  final String json;
  final bool isDemo;
  final double longitude;
  final double latitude;
  final double zoom;
  final String reliefLabel;
  final bool isReliefPreview;
  final bool isCassisReal;

  String get bannerText {
    final terrain = 'Relief terrestre = $reliefLabel.';
    if (isCassisReal) {
      return '$terrain\nCôte = réelle OSM · objets portuaires = réels OSM.\n'
          'Bathymétrie = réelle SHOM : levé 2007–2013 (grille 10 m) / HOMONIM ≈111 m.\n'
          'Aides à la navigation = feux OSM ; autres catégories absentes non affichées.\n'
          'Gris bleu = profondeur indisponible. Ne pas utiliser pour la navigation officielle.';
    }
    if (isReliefPreview) {
      return '$terrain\nAperçu réel : mer unie, sans bathymétrie.\nBathymétrie et objets de la démo = fictifs, non affichés ici.';
    }
    return isDemo
        ? '$terrain\nBathymétrie = fictive · objets nautiques = fictifs.\nÎle et côte fictives — test visuel uniquement.'
        : '$terrain\nDonnées fournies — couverture et fiabilité à vérifier auprès des sources.';
  }

  static Future<MapStyle> load(http.Client client, Uri uri) async {
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Serveur cartographique : HTTP ${response.statusCode}');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['version'] != 8 ||
        data['sources'] is! Map ||
        data['layers'] is! List) {
      throw const FormatException('Style MapLibre v8 attendu');
    }
    final mode = (data['metadata'] as Map?)?['nowave:data_mode'];
    if (mode != 'DEMO_FICTIVE' &&
        mode != 'DONNEES_FOURNIES' &&
        mode != 'RELIEF_REAL_PREVIEW' &&
        mode != 'CASSIS_REAL' &&
        mode != 'REGION_REAL') {
      throw const FormatException('Provenance absente du style NoWave');
    }
    final center = data['center'] as List? ?? [0, 0];
    return MapStyle(
      jsonEncode(data),
      mode == 'DEMO_FICTIVE' || mode == 'RELIEF_REAL_PREVIEW',
      (center[0] as num).toDouble(),
      (center[1] as num).toDouble(),
      (data['zoom'] as num? ?? 10.5).toDouble(),
      reliefLabel:
          (data['metadata'] as Map?)?['nowave:relief_label'] as String? ??
          'non renseigné',
      isReliefPreview: mode == 'RELIEF_REAL_PREVIEW',
      isCassisReal: mode == 'CASSIS_REAL',
    );
  }
}
