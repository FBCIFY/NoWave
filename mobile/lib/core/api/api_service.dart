import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

/// Client HTTP commun à tous les appels au backend.
///
/// Il ajoute l'adresse de base, abandonne après 10 secondes et lève une
/// [ApiException] si la réponse n'est pas un succès. Le token Firebase est
/// ajouté par les services de chaque fonctionnalité (profil, signalements).
class ApiService {
  final http.Client _client;
  final String _baseUrl;

  factory ApiService({
    required http.Client client,
    String baseUrl = ApiConfig.baseUrl,
  }) {
    return ApiService._(client, baseUrl);
  }

  ApiService._(this._client, this._baseUrl);

  Future<String> get(String path, {Map<String, String>? headers}) async {
    final response = await _client
        .get(_resolveUri(path), headers: headers)
        .timeout(const Duration(seconds: 10));

    return _readResponse(response);
  }

  Future<String> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await _client
        .post(_resolveUri(path), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));

    return _readResponse(response);
  }

  /// Envoi `multipart/form-data` d'un fichier (photo). Délai plus long que
  /// les autres appels : jusqu'à 500 Ko sur un réseau mobile parfois lent.
  Future<String> postMultipart(
    String path, {
    Map<String, String>? headers,
    required http.MultipartFile file,
  }) async {
    final request = http.MultipartRequest('POST', _resolveUri(path))
      ..files.add(file);
    if (headers != null) request.headers.addAll(headers);

    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));

    return _readResponse(response);
  }

  Future<String> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await _client
        .patch(_resolveUri(path), headers: headers, body: body)
        .timeout(const Duration(seconds: 10));

    return _readResponse(response);
  }

  Uri _resolveUri(String path) {
    final baseUri = Uri.tryParse(_baseUrl);

    if (baseUri == null ||
        !baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw StateError(
        'API_BASE_URL doit être une adresse HTTP ou HTTPS valide',
      );
    }

    return baseUri.resolve(path);
  }

  String _readResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }

    throw ApiException(statusCode: response.statusCode, body: response.body);
  }
}
