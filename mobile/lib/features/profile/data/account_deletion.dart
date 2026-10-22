import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/device/device_position_reporter.dart';
import '../../../core/device/device_registration.dart';
import '../../auth/data/auth_service.dart';
import 'profile_service.dart';

/// Reprise persistante d'une suppression explicitement confirmée.
/// Aucune erreur HTTP (y compris 401/404) ne prouve la suppression complète :
/// seul un compte Firebase introuvable la prouve, car le serveur efface la base
/// avant Firebase.
class AccountDeletion {
  AccountDeletion({
    required this.profileService,
    required this.authService,
    required this.registration,
    required this.reporter,
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final ProfileService profileService;
  final AuthService authService;
  final DeviceRegistration registration;
  final DevicePositionReporter reporter;
  final Future<SharedPreferences> Function() _preferences;
  static const _key = 'account_deletion';
  bool pending = false;
  bool confirmed = false;
  String? _uid;
  Future<void>? _running;

  Future<bool> restore() async {
    final preferences = await _preferences();
    final saved = preferences.getStringList(_key);
    if (saved == null) return false;
    if (saved.length != 2 || saved.first != authService.currentUser?.uid) {
      // Ne jamais appliquer le journal d'un compte à un autre compte.
      return false;
    }
    _uid = saved.first;
    pending = true;
    confirmed = saved.last == 'confirmed';
    registration.beginSignOut();
    return true;
  }

  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _save(String phase) async {
    final preferences = await _preferences();
    if (!await preferences.setStringList(_key, [_uid!, phase])) {
      throw StateError('Impossible de conserver la reprise de suppression.');
    }
  }

  Future<void> _run() async {
    _uid ??= authService.currentUser?.uid;
    if (_uid == null) throw StateError('Session indisponible.');
    if (!pending) {
      await _save('pending');
      pending = true;
    }
    registration.beginSignOut();
    await reporter.stop();
    await registration.pauseForAccountDeletion();
    if (!confirmed) {
      try {
        await profileService.deleteAccount();
      } catch (_) {
        // Réponse 204 perdue : le jeton d'un compte supprimé ne se renouvelle
        // plus et chaque nouvel essai échouerait.
        if (!await authService.isIdentityDeleted()) rethrow;
      }
      confirmed = true;
    }
    // Retenter l'écriture si elle avait échoué après le 204.
    await _save('confirmed');
    await registration.finishAccountDeletion();
    await authService.signOut();
    registration.completeSignOut();
    final preferences = await _preferences();
    if (!await preferences.remove(_key)) {
      throw StateError('Impossible d’effacer le journal de suppression.');
    }
  }

  /// Sortie sans confirmation du serveur : ferme la session sur ce téléphone
  /// sans appeler l'API. Le journal est gardé : une reconnexion au même compte
  /// reprend la suppression.
  Future<void> leave() async {
    registration.beginSignOut();
    await reporter.stop();
    await registration.finishAccountDeletion();
    await authService.signOut();
    registration.completeSignOut();
  }
}
