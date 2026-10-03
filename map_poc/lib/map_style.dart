import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads the style's provenance before rendering any geographic information.
class MapStyle {
  const MapStyle(
    this.json,
    this.isDemo,
    this.longitude,
    this.latitude,
    this.zoom,
  );

  final String json;
  final bool isDemo;
  final double longitude;
  final double latitude;
  final double zoom;

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
    if (mode != 'DEMO_FICTIVE' && mode != 'DONNEES_FOURNIES') {
      throw const FormatException('Provenance absente du style NoWave');
    }
    final center = data['center'] as List? ?? [0, 0];
    return MapStyle(
      jsonEncode(data),
      mode == 'DEMO_FICTIVE',
      (center[0] as num).toDouble(),
      (center[1] as num).toDouble(),
      (data['zoom'] as num? ?? 10.5).toDouble(),
    );
  }
}
