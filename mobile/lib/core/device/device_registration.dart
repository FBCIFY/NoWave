import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../notifications/notification_permission.dart';
import '../notifications/push_tokens.dart';
import 'device_service.dart';
import 'installation_id_store.dart';

/// Tient l'enregistrement de ce téléphone à jour côté backend.
///
/// Le token FCM n'est envoyé que si le téléphone autorise les notifications ;
/// sinon le backend reçoit `null` et efface l'ancien token (« jeton révoqué »
/// de la doc technique). L'appareil reste enregistré pour sa position GPS.
///
/// Les échecs (réseau, serveur) sont seulement journalisés : le prochain
/// retour dans l'app réessaie.
class DeviceRegistration {
  final DeviceService _devices;
  final PushTokens _pushTokens;
  final NotificationPermissionService _permissions;
  final InstallationIdStore _installationIds;

  StreamSubscription<String>? _tokenSubscription;

  /// Vrai entre [unregister] et le prochain [start] : plus aucun
  /// enregistrement ne part pour le compte qui se déconnecte.
  bool _unregistered = false;

  /// Dernier enregistrement demandé. Les demandes s'enchaînent pour que le
  /// dernier token envoyé soit toujours le plus récent.
  Future<void> _queue = Future.value();

  factory DeviceRegistration({
    required DeviceService devices,
    required PushTokens pushTokens,
    required NotificationPermissionService permissions,
    required InstallationIdStore installationIds,
  }) {
    return DeviceRegistration._(
      devices,
      pushTokens,
      permissions,
      installationIds,
    );
  }

  DeviceRegistration._(
    this._devices,
    this._pushTokens,
    this._permissions,
    this._installationIds,
  );

  /// Enregistre le téléphone, puis le réenregistre à chaque nouveau token FCM.
  Future<void> start() {
    _unregistered = false;
    _tokenSubscription ??= _pushTokens.onTokenRefresh.listen(
      (token) => unawaited(register(refreshedToken: token)),
    );
    return register();
  }

  /// Arrête de suivre les nouveaux tokens FCM.
  Future<void> stop() async {
    final subscription = _tokenSubscription;
    _tokenSubscription = null;
    await subscription?.cancel();
  }

  /// Enregistre le téléphone avec [refreshedToken] (qui vient d'être
  /// renouvelé), ou à défaut le token actuel. Ne lève jamais d'erreur.
  Future<void> register({String? refreshedToken}) {
    return _queue = _queue.then((_) => _register(refreshedToken));
  }

  /// Déconnexion : désactive le téléphone côté backend, invalide son token
  /// FCM et prépare un nouvel identifiant pour le prochain compte.
  ///
  /// À appeler avant `signOut`, qui coupe l'accès au backend. Chaque étape
  /// est tentée même si la précédente échoue (hors ligne) : la déconnexion ne
  /// doit jamais rester bloquée. Ne lève jamais d'erreur.
  Future<void> unregister() {
    _unregistered = true;
    // Après l'enregistrement en cours, pour que le DELETE passe en dernier.
    return _queue = _queue.then((_) => _unregister());
  }

  Future<void> _unregister() async {
    await stop();
    await _attempt('Désactivation du téléphone', _devices.deactivate);
    // Sans ça, le compte suivant recevrait les alertes de l'ancien si le
    // DELETE a échoué.
    await _attempt('Suppression du token FCM', _pushTokens.deleteToken);
    await _attempt('Nouvel identifiant d’installation', _installationIds.reset);
  }

  static Future<void> _attempt(
    String label,
    Future<void> Function() step,
  ) async {
    try {
      await step().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('$label impossible : $error');
    }
  }

  Future<void> _register(String? refreshedToken) async {
    if (_unregistered) return;
    try {
      final allowed =
          await _permissions.getStatus() == NotificationPermission.granted;
      final token = allowed
          ? refreshedToken ?? await _pushTokens.getToken()
          : null;
      try {
        await _devices.register(fcmToken: token);
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
        await _recoverFromConflict(allowed: allowed);
      }
    } catch (error) {
      debugPrint('Enregistrement du téléphone impossible : $error');
    }
  }

  /// 409 : le token FCM ou l'identifiant d'installation est déjà lié à un
  /// autre appareil (déconnexion hors ligne, app réinstallée). On essaie un
  /// nouveau token, puis, si ça ne suffit pas, un nouvel identifiant.
  Future<void> _recoverFromConflict({required bool allowed}) async {
    // Sans token envoyé, seul l'identifiant peut être en conflit.
    if (allowed) {
      await _pushTokens.deleteToken();
      try {
        await _devices.register(fcmToken: await _pushTokens.getToken());
        return;
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
      }
    }

    await _installationIds.reset();
    await _devices.register(
      fcmToken: allowed ? await _pushTokens.getToken() : null,
    );
  }
}
