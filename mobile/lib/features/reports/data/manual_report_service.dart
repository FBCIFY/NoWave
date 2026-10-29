import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_service.dart';
import '../domain/manual_report.dart';

/// Envoie un signalement, manuel ou photo, au backend (`POST api/v1/reports`)
/// et renvoie son identifiant. En mode photo, le JPEG part ensuite à part
/// avec [uploadPhoto].
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

  /// Envoie le JPEG d'un signalement photo déjà publié
  /// (`POST api/v1/reports/{id}/photo`). Un réessai réutilise le même
  /// [reportId] : le backend ne crée jamais de seconde photo.
  Future<void> uploadPhoto({
    required String reportId,
    required Uint8List jpegBytes,
  }) async {
    final token = await _getIdToken();
    final response = await _apiService.postMultipart(
      'api/v1/reports/${Uri.encodeComponent(reportId)}/photo',
      headers: {'Authorization': 'Bearer $token'},
      file: http.MultipartFile.fromBytes(
        'file',
        jpegBytes,
        filename: 'photo.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    final decoded = jsonDecode(response);
    if (decoded is! Map<String, dynamic> ||
        decoded['upload_status'] != 'uploaded') {
      throw const FormatException('L’envoi de la photo n’est pas confirmé.');
    }
  }
}
