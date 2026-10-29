import 'dart:convert';

import '../../../core/api/api_exception.dart';
import '../../../core/api/api_service.dart';
import '../domain/user_profile.dart';
import '../domain/boat.dart';

/// Accès au profil NoWave côté backend (`api/v1/users/me`) : lecture,
/// création, changement du nom d'utilisateur et mise à jour des préférences,
/// avec le token Firebase.
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

  /// Le backend répond 409 `username_already_exists` si le nom est pris.
  Future<UserProfile> updateUsername(String username) async {
    final token = await _getIdToken();

    final response = await _apiService.patch(
      _profilePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'username': username.trim()}),
    );

    return _decodeProfile(response);
  }

  /// Les deux champs peuvent être effacés explicitement avec null.
  Future<UserProfile> updatePersonalInformation({
    required DateTime? dateOfBirth,
    required String? nationality,
  }) async {
    final token = await _getIdToken();
    final date = dateOfBirth == null
        ? null
        : '${dateOfBirth.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth.day.toString().padLeft(2, '0')}';
    final response = await _apiService.patch(
      _profilePath,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'date_of_birth': date,
        'nationality': nationality?.trim().toUpperCase(),
      }),
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

  /// Seul 204 confirme la fin du flux serveur (SQL puis Firebase).
  Future<void> deleteAccount() async {
    final token = await _getIdToken();
    await _apiService.delete(
      _profilePath,
      headers: {'Authorization': 'Bearer $token'},
      expectedStatusCode: 204,
    );
  }

  Future<Boat?> getBoat() async {
    final token = await _getIdToken();
    try {
      return _decodeBoat(
        await _apiService.get(
          '$_profilePath/boat',
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404 && error.code == 'boat_not_found') {
        return null;
      }
      rethrow;
    }
  }

  Future<Boat> saveBoat({
    required bool create,
    required BoatType type,
    required String name,
    required String flagCountry,
  }) async {
    final token = await _getIdToken();
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'boat_type': type.apiValue,
      'name': name.trim().isEmpty ? null : name.trim(),
      'flag_country': flagCountry.trim().isEmpty
          ? null
          : flagCountry.trim().toUpperCase(),
    });
    final response = create
        ? await _apiService.post(
            '$_profilePath/boat',
            headers: headers,
            body: body,
          )
        : await _apiService.patch(
            '$_profilePath/boat',
            headers: headers,
            body: body,
          );
    return _decodeBoat(response);
  }

  Future<void> deleteBoat() async {
    final token = await _getIdToken();
    await _apiService.delete(
      '$_profilePath/boat',
      headers: {'Authorization': 'Bearer $token'},
      expectedStatusCode: 204,
    );
  }

  Boat _decodeBoat(String response) {
    final json = jsonDecode(response);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le bateau reçu est invalide.');
    }
    return Boat.fromJson(json);
  }

  UserProfile _decodeProfile(String response) {
    final json = jsonDecode(response);

    if (json is! Map<String, dynamic>) {
      throw const FormatException('Le profil reçu est invalide.');
    }

    return UserProfile.fromJson(json);
  }
}
