import 'dart:async';

import 'package:flutter/foundation.dart';

/// État de la couche des signalements sur la carte.
enum ReportLayerStatus {
  /// Installation en cours après un chargement de style : rien à signaler.
  pending,

  /// Source et couches absentes : l'installation a échoué (token, réseau)
  /// et sera retentée.
  notInstalled,

  /// Couche en place et tuiles servies.
  installed,

  /// Couche en place, mais les tuiles échouent (réseau, serveur en panne).
  unavailable,
}

/// Suit l'installation de la couche des signalements et l'état de ses
/// tuiles (NW-152), sans dépendre de Mapbox : la carte lui transmet ses
/// événements et il appelle [install] ou [authorize].
///
/// - L'installation manquante est retentée seule, après 15 s, 30 s puis
///   toutes les minutes, et aussi au retour dans l'app ou au renouvellement
///   du token, sans attendre un rechargement du style.
/// - Une seule installation à la fois : pas de source en double.
/// - Un refus pour limite de débit (429) est ignoré, Mapbox redemande la
///   tuile. Toute autre erreur, 503 compris, rend la couche indisponible
///   jusqu'à ce qu'une tuile se charge sans erreur.
class ReportLayerController {
  ReportLayerController({required this._install, required this._authorize});

  final Future<void> Function() _install;
  final Future<void> Function() _authorize;

  /// Attentes avant chaque nouvelle tentative d'installation ; la dernière
  /// se répète.
  @visibleForTesting
  static const installRetryDelays = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  /// Intervalle minimal entre deux envois du token après une tuile en
  /// échec : en déplaçant la carte, les erreurs arrivent par dizaines.
  @visibleForTesting
  static const authorizeInterval = Duration(seconds: 30);

  /// Une tuile chargée ne prouve le retour que si aucune erreur n'arrive
  /// dans cet intervalle, avant ou après : Mapbox signale aussi comme
  /// « chargée » une tuile qui vient d'échouer.
  @visibleForTesting
  static const recoveryQuietPeriod = Duration(seconds: 2);

  final ValueNotifier<ReportLayerStatus> _status = ValueNotifier(
    ReportLayerStatus.pending,
  );

  ValueListenable<ReportLayerStatus> get status => _status;

  bool _installing = false;

  /// Un style a été chargé pendant une installation : on recommence une
  /// fois celle-ci terminée, la précédente visait l'ancien style.
  bool _reinstallRequested = false;

  int _failedInstalls = 0;
  Timer? _retryTimer;
  bool _paused = false;
  bool _disposed = false;

  /// Token envoyé il y a moins de [authorizeInterval].
  Timer? _authorizeCooldown;

  /// Tuile en échec il y a moins de [recoveryQuietPeriod].
  Timer? _recentTileError;

  Timer? _recoveryTimer;

  /// Nouveau style : ses couches sont vides, on installe la nôtre.
  void styleLoaded() {
    _cancelRecovery();
    _retryTimer?.cancel();
    _retryTimer = null;
    _failedInstalls = 0;
    _setStatus(ReportLayerStatus.pending);
    if (_installing) {
      _reinstallRequested = true;
      return;
    }
    unawaited(_runInstall());
  }

  /// L'app n'est plus visible : plus de nouvelle tentative.
  void pause() {
    _paused = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Retour dans l'app : réinstalle si besoin, sinon redonne le token.
  void resume() {
    _paused = false;
    if (_status.value == ReportLayerStatus.notInstalled) {
      _retryNow();
    } else {
      _sendToken();
    }
  }

  /// Renouvellement périodique du token, qui sert aussi de tentative
  /// d'installation si la couche manque.
  void renewToken() {
    if (_status.value == ReportLayerStatus.notInstalled) {
      _retryNow();
    } else {
      _sendToken();
    }
  }

  /// Une tuile des signalements a échoué ; [message] est celui de Mapbox.
  void tileError(String message) {
    if (isRateLimited(message)) return;
    _recentTileError?.cancel();
    _recentTileError = Timer(recoveryQuietPeriod, () {
      _recentTileError = null;
    });
    _cancelRecovery();
    if (_status.value == ReportLayerStatus.installed) {
      _setStatus(ReportLayerStatus.unavailable);
    }
    // Un 401 vient d'un token expiré : on le redonne, sans insister.
    if (_authorizeCooldown == null) _sendToken();
  }

  /// Une tuile des signalements s'est chargée.
  void tileLoaded() {
    if (_status.value != ReportLayerStatus.unavailable) return;
    if (_recoveryTimer != null || _recentTileError != null) return;
    _recoveryTimer = Timer(recoveryQuietPeriod, () {
      _recoveryTimer = null;
      if (_status.value == ReportLayerStatus.unavailable) {
        _setStatus(ReportLayerStatus.installed);
      }
    });
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _authorizeCooldown?.cancel();
    _recentTileError?.cancel();
    _cancelRecovery();
    _status.dispose();
  }

  /// Vrai si la tuile a été refusée par la limite de débit du serveur :
  /// Mapbox la redemande lui-même un peu plus tard. Mapbox ne transmet que
  /// le code HTTP, pas le corps de la réponse.
  static bool isRateLimited(String message) =>
      RegExp(r'status code 429\b').hasMatch(message);

  void _retryNow() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_installing) unawaited(_runInstall());
  }

  Future<void> _runInstall() async {
    _installing = true;
    var installed = false;
    try {
      await _install();
      installed = true;
    } catch (error) {
      debugPrint('Couche des signalements non installée : $error');
    } finally {
      _installing = false;
    }
    if (_disposed) return;

    if (_reinstallRequested) {
      _reinstallRequested = false;
      unawaited(_runInstall());
      return;
    }
    if (installed) {
      _failedInstalls = 0;
      _startAuthorizeCooldown();
      _setStatus(ReportLayerStatus.installed);
    } else {
      _setStatus(ReportLayerStatus.notInstalled);
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_paused) return;
    final index = _failedInstalls < installRetryDelays.length
        ? _failedInstalls
        : installRetryDelays.length - 1;
    _failedInstalls++;
    _retryTimer = Timer(installRetryDelays[index], _retryNow);
  }

  void _startAuthorizeCooldown() {
    _authorizeCooldown?.cancel();
    _authorizeCooldown = Timer(authorizeInterval, () {
      _authorizeCooldown = null;
    });
  }

  void _sendToken() {
    _startAuthorizeCooldown();
    unawaited(
      _authorize().catchError((Object error) {
        debugPrint('Token des signalements non renouvelé : $error');
      }),
    );
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  void _setStatus(ReportLayerStatus status) {
    if (!_disposed) _status.value = status;
  }
}
