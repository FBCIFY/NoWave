import 'dart:convert';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../domain/user_profile.dart';

/// Accès au profil NoWave côté backend (`api/v1/users/me`) : lecture,
/// création et mise à jour des préférences, avec le token Firebase.
class ProfileService {
  static const String _profilePath = 'api/v1/users/me';

  final ApiService _apiService;
  final Future<String> Function() _getIdToken;

  factory ProfileService({
    required ApiService apiService,
    required Future<String> Function() getIdToken,
  }) {
    return ProfileService._(apiService, getIdToken);
  }

  ProfileService._(this._apiService, this._getIdToken);

  /// Renvoie `null` si le backend répond 404 : le profil n'existe pas encore.
  Future<UserProfile?> getCurrentProfile() async {
    final token = await _getIdToken();

    try {
      final response = await _apiService.get(
        _profilePath,
        headers: {'Authorization': 'Bearer $token'},
      );

      return _decodeProfile(response);
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  Future<UserProfile> createProfile({required String username}) async {
    final token = await _getIdToken();

    final response = await _apiService.post(
      _profilePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'username': username.trim()}),
    );

    return _decodeProfile(response);
  }

  /// N'envoie que les préférences non nulles (PATCH partiel).
  Future<UserProfile> updatePreferences({
    bool? showUserName,
    bool? showBoatInfo,
    bool? notificationsEnabled,
  }) async {
    final changes = <String, bool>{
      'show_user_name': ?showUserName,
      'show_boat_info': ?showBoatInfo,
      'notifications_enabled': ?notificationsEnabled,
    };

    if (changes.isEmpty) {
      throw ArgumentError('Aucune préférence à mettre à jour.');
    }

    final token = await _getIdToken();

    final response = await _apiService.patch(
      _profilePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(changes),
    );

    return _decodeProfile(response);
  }

  UserProfile _decodeProfile(String response) {
    final json = jsonDecode(response);

    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le profil reçu est invalide.');
    }

    return UserProfile.fromJson(json);
  }
}
