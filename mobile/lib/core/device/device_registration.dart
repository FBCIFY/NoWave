import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../notifications/notification_permission.dart';
import '../notifications/push_tokens.dart';
import 'device_service.dart';
import 'installation_id_store.dart';

enum _RegistrationState { active, cleaning, cleaned, signedOut }

/// Tient l'enregistrement de ce téléphone à jour côté backend.
///
/// Le token FCM n'est envoyé que si le téléphone autorise les notifications ;
/// sinon le backend reçoit `null` et efface l'ancien token (« jeton révoqué »
/// de la doc technique). L'appareil reste enregistré pour sa position GPS.
///
/// Les échecs d'enregistrement sont journalisés et réessayés au retour dans
/// l'app. Un échec de nettoyage bloque la déconnexion pour garder la session
/// qui permet de réessayer avec le même identifiant.
class DeviceRegistration {
  final DeviceService _devices;
  final PushTokens _pushTokens;
  final NotificationPermissionService _permissions;
  final InstallationIdStore _installationIds;

  StreamSubscription<String>? _tokenSubscription;

  _RegistrationState _state = _RegistrationState.active;

  /// Reste vrai jusqu'au démarrage de la session suivante, même après un
  /// échec : les reprises du cycle de vie ne doivent pas relancer le GPS.
  bool get isSigningOut => _state != _RegistrationState.active;

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
    if (_state == _RegistrationState.cleaning ||
        _state == _RegistrationState.cleaned) {
      return Future.value();
    }
    _state = _RegistrationState.active;
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
  /// À appeler avant `signOut`, qui coupe l'accès au backend. Un échec du
  /// DELETE conserve l'identifiant et remonte à l'appelant : la session doit
  /// rester ouverte pour une nouvelle tentative authentifiée.
  Future<void> unregister() {
    beginSignOut();
    // Après l'enregistrement en cours, pour que le DELETE passe en dernier.
    final result = _queue.then((_) => _unregister());
    // L'appelant reçoit l'erreur, mais elle n'empoisonne pas les tentatives
    // suivantes dans la file.
    _queue = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  /// Ferme immédiatement les reprises GPS/FCM, avant d'attendre les envois
  /// GPS en cours puis d'appeler [unregister].
  void beginSignOut() {
    if (_state == _RegistrationState.active) {
      _state = _RegistrationState.cleaning;
    }
  }

  /// Après un échec, l'utilisateur renonce à se déconnecter : il reste sur
  /// le compte actuel, qui peut de nouveau enregistrer le téléphone. À
  /// appeler seulement quand [unregister] a rendu la main.
  void cancelSignOut() {
    if (_state == _RegistrationState.signedOut) {
      throw StateError('La session est déjà fermée.');
    }
    _state = _RegistrationState.active;
  }

  /// À appeler seulement après la fermeture effective de la session Firebase.
  /// Un remontage de l'écran ne suffit pas à autoriser un nouvel enregistrement.
  void completeSignOut() {
    if (_state != _RegistrationState.cleaned) {
      throw StateError('Le nettoyage de l’appareil n’est pas terminé.');
    }
    _state = _RegistrationState.signedOut;
  }

  Future<void> _unregister() async {
    // Session ouverte après une déconnexion, sans atteindre l'accueil (compte
    // sans profil ou suspendu) : l'identifiant a été oublié à la déconnexion
    // précédente et rien n'a été enregistré depuis, rien à nettoyer.
    if (_state == _RegistrationState.signedOut) {
      _state = _RegistrationState.cleaned;
      return;
    }
    if (_state == _RegistrationState.cleaned) return;
    await stop();
    try {
      await _devices.deactivate();
    } on ApiException catch (error) {
      // Absence confirmée pour ce compte : rien ne reste à désactiver.
      // Un 404 de proxy ou d'une route absente n'est pas une confirmation.
      if (error.statusCode != 404 ||
          (error.code != 'device_not_found' &&
              error.code != 'user_not_found')) {
        rethrow;
      }
    } finally {
      // Même si le serveur ne répond pas, on tente d'invalider le token.
      // Son succès seul ne permet pas d'abandonner l'ancien appareil.
      await _attempt('Suppression du token FCM', _pushTokens.deleteToken);
    }
    // Seulement après confirmation serveur. Une erreur du stockage remonte
    // aussi : elle ne doit pas être masquée par la déconnexion Firebase.
    await _installationIds.reset();
    _state = _RegistrationState.cleaned;
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
    if (isSigningOut) return;
    try {
      final allowed =
          await _permissions.getStatus() == NotificationPermission.granted;
      final token = allowed
          ? refreshedToken ?? await _pushTokens.getToken()
          : null;
      if (isSigningOut) return;
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
    if (isSigningOut) return;
    // Sans token envoyé, seul l'identifiant peut être en conflit.
    if (allowed) {
      await _pushTokens.deleteToken();
      if (isSigningOut) return;
      try {
        final token = await _pushTokens.getToken();
        if (isSigningOut) return;
        await _devices.register(fcmToken: token);
        return;
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
      }
    }

    if (isSigningOut) return;
    await _installationIds.reset();
    final token = allowed ? await _pushTokens.getToken() : null;
    if (isSigningOut) return;
    await _devices.register(fcmToken: token);
  }
}
