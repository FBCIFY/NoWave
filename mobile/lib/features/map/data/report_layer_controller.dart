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
/// - Seul un 401 (token expiré) fait redonner le token.
/// - En arrière-plan, Mapbox est coupé du réseau : les alertes gardent l'app
///   en vie (NW-159), et il redemanderait sinon les tuiles visibles toutes
///   les 15 s. Au retour, le token est redonné avant de le rebrancher. Un
///   seul appel à Mapbox à la fois, et un appel en échec est retenté : le
///   réseau finit toujours dans le dernier état demandé.
class ReportLayerController {
  ReportLayerController({
    required this._install,
    required this._authorize,
    required this._connectNetwork,
  });

  final Future<void> Function() _install;
  final Future<void> Function() _authorize;

  /// Coupe (false) ou rebranche (true) le réseau de Mapbox, fond de carte
  /// compris.
  final Future<void> Function(bool connected) _connectNetwork;

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

  /// Attente maximale du token au retour dans l'app avant de rebrancher
  /// Mapbox : avec un réseau faible, le fond de carte ne reste pas coupé.
  @visibleForTesting
  static const reconnectTimeout = Duration(seconds: 5);

  /// Attente avant de retenter une coupure ou un rebranchement refusé par
  /// Mapbox.
  @visibleForTesting
  static const networkRetryDelay = Duration(seconds: 5);

  final ValueNotifier<ReportLayerStatus> _status = ValueNotifier(
    ReportLayerStatus.pending,
  );

  ValueListenable<ReportLayerStatus> get status => _status;

  bool _installing = false;
  bool _tileFailure = false;

  /// Un style a été chargé pendant une installation : on recommence une
  /// fois celle-ci terminée, la précédente visait l'ancien style.
  bool _reinstallRequested = false;

  int _failedInstalls = 0;
  Timer? _retryTimer;
  bool _paused = false;
  bool _disposed = false;

  /// Réseau de Mapbox demandé : coupé par [pause], rebranché ensuite.
  bool _networkWanted = true;

  /// Dernier état confirmé par Mapbox, connecté au démarrage.
  bool _networkConnected = true;

  /// Appel à Mapbox en cours : les suivants attendent qu'il se termine.
  bool _changingNetwork = false;

  Timer? _networkRetry;

  /// Mapbox coupé du réseau par [pause], ou en cours de coupure ou de
  /// rebranchement : ses requêtes échouent sans que le réseau ou le serveur
  /// soient en panne. Faux si Mapbox a refusé la coupure.
  bool get networkCut => !_networkConnected || _changingNetwork;

  /// Token envoyé il y a moins de [authorizeInterval].
  Timer? _authorizeCooldown;

  /// Tuile en échec il y a moins de [recoveryQuietPeriod].
  Timer? _recentTileError;

  /// Tuiles en échec pendant [_recentTileError] : Mapbox les signale aussi
  /// comme chargées, ce qui ne prouve rien.
  final _recentlyFailedTiles = <String>{};

  /// Une autre tuile s'est chargée pendant [_recentTileError] : la
  /// confirmation du retour démarre à la fin de cette période.
  bool _tileLoadedDuringRecentError = false;

  Timer? _recoveryTimer;

  /// Nouveau style : ses couches sont vides, on installe la nôtre.
  void styleLoaded() {
    _cancelRecovery();
    _tileFailure = false;
    _recentTileError?.cancel();
    _recentTileError = null;
    _recentlyFailedTiles.clear();
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

  /// L'app n'est plus visible : plus de nouvelle tentative, et plus de
  /// requête de Mapbox.
  void pause() {
    _paused = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _setNetwork(connected: false);
  }

  /// Retour dans l'app : réinstalle si besoin, sinon redonne le token, puis
  /// rebranche le réseau. Mapbox redemande alors aussitôt les tuiles
  /// périmées : avec le token d'abord, elles ne tombent pas en 401 après un
  /// long arrière-plan. Au-delà de [reconnectTimeout], on rebranche sans lui.
  void resume() {
    _paused = false;
    if (_status.value == ReportLayerStatus.notInstalled) {
      // L'installation redonne elle-même le token avant d'ajouter la source.
      _setNetwork(connected: true);
      _retryNow();
      return;
    }
    unawaited(
      _sendToken().timeout(reconnectTimeout, onTimeout: () {}).whenComplete(() {
        // Repartie en arrière-plan entre-temps : le réseau reste coupé.
        if (!_paused && !_disposed) _setNetwork(connected: true);
      }),
    );
  }

  /// Renouvellement périodique du token, qui sert aussi de tentative
  /// d'installation si la couche manque.
  void renewToken() {
    if (_status.value == ReportLayerStatus.notInstalled) {
      _retryNow();
    } else {
      unawaited(_sendToken());
    }
  }

  /// Une tuile des signalements a échoué ; [message] est celui de Mapbox,
  /// [tile] identifie la tuile (`z/x/y`) quand Mapbox la donne.
  void tileError(String message, {String? tile}) {
    if (networkCut || isRateLimited(message)) return;
    _tileFailure = true;
    if (tile != null) _recentlyFailedTiles.add(tile);
    _recentTileError?.cancel();
    _recentTileError = Timer(recoveryQuietPeriod, _endRecentTileError);
    _cancelRecovery();
    if (_status.value == ReportLayerStatus.installed) {
      _setStatus(ReportLayerStatus.unavailable);
    }
    // Un 401 vient d'un token expiré : on le redonne, sans insister. Un
    // nouveau token ne change rien à un 403 ou à une panne.
    if (isUnauthorized(message) && _authorizeCooldown == null) {
      unawaited(_sendToken());
    }
  }

  /// Une tuile des signalements s'est chargée ; [tile] comme pour
  /// [tileError].
  void tileLoaded({String? tile}) {
    if (_status.value != ReportLayerStatus.unavailable) return;
    if (_recentTileError != null) {
      // Seule une tuile qui n'a pas échoué prouve que le serveur répond.
      if (tile != null && !_recentlyFailedTiles.contains(tile)) {
        _tileLoadedDuringRecentError = true;
      }
      return;
    }
    _startRecovery();
  }

  void dispose() {
    _disposed = true;
    // Carte fermée en arrière-plan : la prochaine doit retrouver le réseau.
    // Un rebranchement refusé reste retenté après la fermeture.
    _setNetwork(connected: true);
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

  /// Vrai si la tuile a été refusée faute de token valide.
  static bool isUnauthorized(String message) =>
      RegExp(r'status code 401\b').hasMatch(message);

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
      _setStatus(
        _tileFailure
            ? ReportLayerStatus.unavailable
            : ReportLayerStatus.installed,
      );
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

  Future<void> _sendToken() {
    _startAuthorizeCooldown();
    return _authorize().catchError((Object error) {
      debugPrint('Token des signalements non renouvelé : $error');
    });
  }

  void _setNetwork({required bool connected}) {
    _networkWanted = connected;
    unawaited(_applyNetwork());
  }

  /// Applique à Mapbox le dernier état demandé, un appel à la fois : un
  /// retour dans l'app pendant la coupure rebranche le réseau juste après
  /// elle. Un appel en échec est retenté après [networkRetryDelay].
  Future<void> _applyNetwork() async {
    if (_changingNetwork) return;
    _networkRetry?.cancel();
    _networkRetry = null;
    if (_networkConnected == _networkWanted) return;
    _changingNetwork = true;
    try {
      while (_networkConnected != _networkWanted) {
        final connected = _networkWanted;
        await _connectNetwork(connected);
        _networkConnected = connected;
      }
    } catch (error) {
      debugPrint('Réseau de Mapbox non modifié : $error');
      _networkRetry = Timer(networkRetryDelay, () {
        _networkRetry = null;
        unawaited(_applyNetwork());
      });
    } finally {
      _changingNetwork = false;
    }
  }

  void _endRecentTileError() {
    _recentTileError = null;
    _recentlyFailedTiles.clear();
    if (_tileLoadedDuringRecentError) {
      _tileLoadedDuringRecentError = false;
      _startRecovery();
    }
  }

  /// Rétablit la couche si aucune erreur n'arrive d'ici
  /// [recoveryQuietPeriod].
  void _startRecovery() {
    if (_recoveryTimer != null) return;
    _recoveryTimer = Timer(recoveryQuietPeriod, () {
      _recoveryTimer = null;
      if (_status.value == ReportLayerStatus.unavailable) {
        _tileFailure = false;
        _setStatus(ReportLayerStatus.installed);
      }
    });
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _tileLoadedDuringRecentError = false;
  }

  void _setStatus(ReportLayerStatus status) {
    if (!_disposed) _status.value = status;
  }
}
