import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

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
