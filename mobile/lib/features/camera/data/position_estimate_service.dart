import 'dart:convert';

import '../../../core/api/api_service.dart';
import '../domain/photo_capture.dart';
import '../domain/position_estimate.dart';

/// Demande au backend la position de l'objet photographié
/// (`POST api/v1/position-estimates`). Rien n'est enregistré côté serveur.
class PositionEstimateService {
  factory PositionEstimateService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
  }) => PositionEstimateService._(apiService, getIdToken);

  PositionEstimateService._(this._apiService, this._getIdToken);

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;

  /// Renvoie null si le backend ne peut pas estimer la position.
  Future<PositionEstimate?> estimate(
    PhotoCaptureMeasurements measurements,
  ) async {
    final token = await _getIdToken();
    final response = await _apiService.post(
      'api/v1/position-estimates',
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(measurements.toJson()),
    );

    return PositionEstimate.fromJson(jsonDecode(response));
  }
}
