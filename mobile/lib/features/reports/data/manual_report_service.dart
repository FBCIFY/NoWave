import 'dart:convert';

import '../../../core/api/api_service.dart';
import '../domain/manual_report.dart';

/// Envoie un signalement manuel au backend (`POST api/v1/reports`) et
/// renvoie son identifiant.
class ManualReportService {
  factory ManualReportService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
  }) => ManualReportService._(apiService, getIdToken);

  ManualReportService._(this._apiService, this._getIdToken);

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;

  Future<String> createReport(ManualReportRequest request) async {
    final token = await _getIdToken();
    final response = await _apiService.post(
      'api/v1/reports',
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(request.toJson()),
    );

    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        (decoded['id'] as String).isEmpty) {
      throw const FormatException('Le signalement reçu est invalide.');
    }
    return decoded['id'] as String;
  }
}
