import 'package:flutter/foundation.dart';

/// Un serveur et un style communs à Android et iOS. Aucune clé fournisseur.
class MapConfig {
  static const String styleUrl = String.fromEnvironment('NOWAVE_STYLE_URL');

  static Uri styleUri(String value, {bool production = kReleaseMode}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Configurez NOWAVE_STYLE_URL avec l’adresse HTTP(S) du serveur NoWave.',
      );
    }
    if (production && uri.scheme != 'https') {
      throw const FormatException('La carte en production nécessite HTTPS.');
    }
    return uri;
  }
}
