import 'dart:convert';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../domain/report_detail.dart';

/// Le signalement n'est plus disponible : supprimé, expiré ou introuvable.
class ReportNotFoundException implements Exception {
  const ReportNotFoundException();

  @override
  String toString() => 'Signalement plus disponible';
}

/// Lit la fiche d'un signalement touché sur la carte
/// (`GET api/v1/reports/{id}`).
class ReportDetailService {
  factory ReportDetailService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
  }) => ReportDetailService._(apiService, getIdToken);

  ReportDetailService._(this._apiService, this._getIdToken);

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;

  /// Lève [ReportNotFoundException] si le backend répond 404 ; les autres
  /// erreurs HTTP restent des [ApiException].
  Future<ReportDetail> fetchReport(String reportId) async {
    final token = await _getIdToken();
    final String response;
    try {
      response = await _apiService.get(
        'api/v1/reports/${Uri.encodeComponent(reportId)}',
        headers: {'Authorization': 'Bearer $token'},
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) throw const ReportNotFoundException();
      rethrow;
    }

    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Le signalement reçu est invalide.');
    }
    return ReportDetail.fromJson(decoded);
  }
}
