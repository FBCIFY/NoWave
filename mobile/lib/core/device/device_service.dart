import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_service.dart';
import 'device_position.dart';
import 'installation_id_store.dart';

/// Ce téléphone vu par le backend (`api/v1/devices/current`) : token FCM,
/// dernière position GPS et désactivation à la déconnexion.
///
/// Tous les appels utilisent l'identifiant de [InstallationIdStore] et lèvent
/// une `ApiException` si le backend refuse.
class DeviceService {
  static const String _devicePath = 'api/v1/devices/current';
  static const String _positionPath = 'api/v1/devices/current/position';

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;
  final InstallationIdStore _installationIds;
  final String _platform;

  factory DeviceService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
    required InstallationIdStore installationIds,
    String? platform,
  }) {
    return DeviceService._(
      apiService,
      getIdToken,
      installationIds,
      platform ?? _currentPlatform(),
    );
  }

  DeviceService._(
    this._apiService,
    this._getIdToken,
    this._installationIds,
    this._platform,
  );

  /// Enregistre l'appareil, ou le met à jour s'il l'est déjà.
  ///
  /// Sans [fcmToken] (notifications refusées), le backend efface le token
  /// précédent : ce téléphone ne reçoit plus d'alertes. Un 409 signale un
  /// identifiant d'installation ou un token déjà pris par un autre compte.
  Future<void> register({String? fcmToken}) async {
    final token = await _getIdToken();
    final installationId = await _installationIds.read();

    await _apiService.put(
      _devicePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'installation_id': installationId,
        'platform': _platform,
        'fcm_token': fcmToken,
      }),
    );
  }

  /// Envoie une mesure GPS.
  ///
  /// Le backend répond 404 si l'appareil n'est plus actif (il faut le
  /// réenregistrer) et 409 s'il connaît déjà une mesure plus récente.
  Future<void> sendPosition(DevicePosition position) async {
    final token = await _getIdToken();
    final installationId = await _installationIds.read();

    await _apiService.put(
      _positionPath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Installation-ID': installationId,
      },
      body: jsonEncode(position.toJson()),
    );
  }

  /// Désactive l'appareil : il ne reçoit plus d'alertes et son token FCM est
  /// effacé. À appeler avant la déconnexion Firebase, qui retire le token.
  Future<void> deactivate() async {
    final token = await _getIdToken();
    final installationId = await _installationIds.read();

    await _apiService.delete(
      _devicePath,
      headers: {
        'Authorization': 'Bearer $token',
        'X-Installation-ID': installationId,
      },
    );
  }

  static String _currentPlatform() {
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
