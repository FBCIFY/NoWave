/// Adresses NoWave fournies par l'environnement de compilation.
/// La base marine facultative ne concerne que les sources publiques de carte.
class ApiConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _marineBaseUrl = String.fromEnvironment(
    'MARINE_API_BASE_URL',
  );

  /// Même validation et normalisation que la base principale dans [resolve].
  /// Une valeur vide, y compris des espaces seuls, conserve le backend principal.
  static String get marineBaseUrl =>
      _marineBaseUrl.trim().isEmpty ? baseUrl : _marineBaseUrl;

  /// Résout un chemin applicatif sans perdre le préfixe du reverse proxy.
  /// Un appel métier ne peut pas rediriger son token vers une URL absolue.
  static Uri resolve(
    String path, {
    String baseUrl = ApiConfig.baseUrl,
    Map<String, String> queryParameters = const {},
  }) {
    final value = baseUrl.trim();
    final base = Uri.tryParse(value);
    if (base == null ||
        !base.hasAuthority ||
        base.host.isEmpty ||
        !['http', 'https'].contains(base.scheme) ||
        base.userInfo.isNotEmpty ||
        base.hasFragment ||
        RegExp(r'\s').hasMatch(value) ||
        base.port < 1 ||
        base.port > 65535) {
      throw StateError(
        'API_BASE_URL doit être une adresse HTTP ou HTTPS valide, '
        'sans identifiants ni fragment.',
      );
    }
    final relative = Uri.tryParse(path);
    if (relative == null ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasFragment ||
        relative.pathSegments.any((segment) => segment == '..')) {
      throw ArgumentError('Un chemin API relatif est requis.');
    }
    final root = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/',
    );
    final resolved = root.resolve(path.replaceFirst(RegExp(r'^/+'), ''));
    if (!resolved.path.startsWith(root.path)) {
      throw ArgumentError(
        'Le chemin API doit rester dans le préfixe du backend.',
      );
    }
    final parameters = <String, dynamic>{
      ...base.queryParametersAll,
      ...relative.queryParametersAll,
      ...queryParameters,
    };
    return resolved.replace(
      queryParameters: parameters.isEmpty ? null : parameters,
    );
  }

  static String endpoint(
    String path, {
    String baseUrl = ApiConfig.baseUrl,
    Map<String, String> queryParameters = const {},
  }) => _templateString(
    resolve(path, baseUrl: baseUrl, queryParameters: queryParameters),
  );

  static String tileTemplate(
    String family, {
    String extension = 'pbf',
    String baseUrl = ApiConfig.baseUrl,
    Map<String, String> queryParameters = const {},
  }) => endpoint(
    'api/v1/map/$family/{z}/{x}/{y}.$extension',
    baseUrl: baseUrl,
    queryParameters: queryParameters,
  );

  /// Aussi utilisé pour les URLs injectées dans les tests de rendu.
  static String withQueryParameters(
    String url,
    Map<String, String> parameters,
  ) {
    final uri = Uri.parse(url);
    final merged = <String, dynamic>{...uri.queryParametersAll, ...parameters};
    return _templateString(
      uri.replace(queryParameters: merged.isEmpty ? null : merged),
    );
  }

  // Uri encode les accolades. Mapbox doit recevoir les trois jetons littéraux.
  static String _templateString(Uri uri) {
    var value = uri.toString();
    for (final axis in ['z', 'x', 'y']) {
      value = value.replaceAll('%7B$axis%7D', '{$axis}');
    }
    return value;
  }
}
