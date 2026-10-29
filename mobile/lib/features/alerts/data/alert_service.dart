import 'dart:convert';

import '../../../core/api/api_service.dart';
import '../domain/alert.dart';

/// Adaptateur réel ; aucune donnée de démonstration en production.
class AlertService {
  factory AlertService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
  }) => AlertService._(apiService, getIdToken);
  AlertService._(this._api, this._getIdToken);
  final ApiService _api;
  final Future<String> Function() _getIdToken;

  Future<AlertPage> fetchPage({int page = 1, int limit = 20}) async {
    if (page < 1 || limit < 1) throw ArgumentError('Pagination invalide.');
    final token = await _getIdToken();
    final response = await _api.get(
      'api/v1/users/me/alerts?page=$page&limit=$limit',
      headers: {'Authorization': 'Bearer $token'},
    );
    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Historique invalide.');
    }
    final result = AlertPage.fromJson(decoded);
    if (result.page != page || result.limit != limit) {
      throw const FormatException('Page inattendue.');
    }
    return result;
  }
}
