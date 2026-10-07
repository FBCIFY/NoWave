import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
/// (`GET api/v1/reports/{id}`) et sa photo.
class ReportDetailService {
  factory ReportDetailService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
    http.Client? photoClient,
  }) => ReportDetailService._(
    apiService,
    getIdToken,
    photoClient ?? http.Client(),
  );

  ReportDetailService._(this._apiService, this._getIdToken, this._photoClient);

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;
  final http.Client _photoClient;

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

  /// Télécharge la photo depuis l'URL signée de la fiche (valable cinq
  /// minutes). Pas de token Firebase : la signature suffit, et un en-tête
  /// `Authorization` ferait refuser la requête par le stockage.
  ///
  /// Lève une [ApiException] hors 2xx : 403 si l'URL a expiré ou si l'accès
  /// est refusé, le stockage ne distinguant pas les deux.
  Future<Uint8List> fetchPhoto(String url) async {
    // Jusqu'à 500 Ko sur un réseau mobile parfois lent.
    final response = await _photoClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(statusCode: response.statusCode, body: response.body);
    }
    return response.bodyBytes;
  }
}
