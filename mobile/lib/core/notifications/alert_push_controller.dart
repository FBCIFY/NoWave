import 'dart:async';
import 'dart:collection';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../features/alerts/domain/alert.dart';
import 'alert_push_source.dart';

/// Capture avant que le profil soit prêt ; navigation seulement lorsqu'un
/// accueil autorisé attache son callback. Aucune navigation en isolate background.
class AlertPushController extends ChangeNotifier {
  AlertPushController({required this.source, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final AlertPushSource source;
  final DateTime Function() _now;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  final _pending = Queue<AlertPush>();
  final _displayed = <String, DateTime>{};
  final _opened = <String, DateTime>{};
  final _reserved = <String, DateTime>{};
  Future<void> Function(AlertPush)? _navigate;
  AlertPush? foreground;
  String? notice;
  String? _uid;
  bool _sessionKnown = false;
  bool _started = false;
  bool _disposed = false;
  bool _ready = false;
  int _attempt = 0;
  AlertPush? _failed;
  bool get ready => _ready;
  int get sessionEpoch => _generation;
  bool get canRetry => _failed != null && _uid != null && _ready;

  /// SDK redelivery stays deduplicated; retry requires an explicit action.
  void retry() {
    final push = _failed;
    if (!canRetry || push == null) return;
    for (final key in _keys(push)) {
      _reserved.remove(key);
    }
    _failed = null;
    open(push);
  }

  void setReady(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    if (!ready) {
      _generation++;
      _failed = null;
      _reserved.clear();
      for (final push in _pending) {
        _remember(_reserved, push);
      }
    }
    if (ready) scheduleMicrotask(_drain);
  }

  int _generation = 0;

  void setSession(String? uid) {
    if (_sessionKnown && _uid != uid) {
      _generation++;
      _pending.clear();
      _displayed.clear();
      _opened.clear();
      _reserved.clear();
      foreground = null;
      notice = null;
      _navigate = null;
      _failed = null;
      _ready = false;
    }
    // Le premier utilisateur connecté peut reprendre le tap de lancement.
    _sessionKnown = _sessionKnown || uid != null;
    _uid = uid;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _foregroundSubscription = source.foreground.listen(
      (m) => _receive(m, opened: false),
      onError: _sourceError,
    );
    _openedSubscription = source.opened.listen(
      (m) => _receive(m, opened: true),
      onError: _sourceError,
    );
    final generation = _generation;
    try {
      final message = await source.initialMessage();
      if (!_disposed && generation == _generation && message != null) {
        _receive(message, opened: true);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) _sourceError(null);
    }
  }

  void _sourceError(Object? _) {
    if (_disposed) return;
    notice = 'Notifications indisponibles. Consultez l’historique des alertes.';
    notifyListeners();
  }

  void _receive(RemoteMessage message, {required bool opened}) {
    if (_disposed) return;
    try {
      final push = AlertPush.fromData(
        message.data,
        messageId: message.messageId,
      );
      if (opened) {
        open(push);
        return;
      }
      if (_uid == null ||
          push.recipientFirebaseUid != _uid ||
          !_ready ||
          push.expired(_now()) ||
          !_remember(_displayed, push)) {
        return;
      }
      foreground = push;
      notifyListeners();
    } catch (_) {
      if (opened) {
        notice = 'Cette notification est invalide. Consultez l’historique des alertes.';
        notifyListeners();
      }
    }
  }

  bool _remember(Map<String, DateTime> seen, AlertPush push) {
    seen.removeWhere((_, expiry) => !expiry.isAfter(_now()));
    final keys = _keys(push);
    if (keys.any(seen.containsKey)) return false;
    for (final key in keys) {
      seen[key] = push.expiresAt;
    }
    while (seen.length > 1536) {
      seen.remove(seen.keys.first);
    }
    return true;
  }

  List<String> _keys(AlertPush push) => [
    'alert:${push.alert.id}',
    'event:${push.alert.eventKey}',
    if (push.messageId != null) 'message:${push.messageId}',
  ];

  void _rejectAccount() {
    notice = 'Cette notification ne peut pas être ouverte avec ce compte. Consultez l’historique des alertes.';
    notifyListeners();
  }

  void open(AlertPush push) {
    if (_disposed || (_sessionKnown && _uid == null)) return;
    if (push.recipientFirebaseUid == null ||
        (_uid != null && push.recipientFirebaseUid != _uid)) {
      _rejectAccount();
      return;
    }
    if (push.expired(_now())) {
      notice =
          'Cette alerte a expiré. Le signalement peut ne plus être disponible.';
      notifyListeners();
      return;
    }
    _opened.removeWhere((_, expiry) => !expiry.isAfter(_now()));
    if (_keys(push).any(_opened.containsKey) || !_remember(_reserved, push)) {
      return;
    }
    _failed = null;
    if (_pending.length == 32) {
      final discarded = _pending.removeFirst();
      for (final key in _keys(discarded)) {
        _reserved.remove(key);
      }
    }
    _pending.add(push);
    _drain();
  }

  void attach(Future<void> Function(AlertPush) navigate) {
    _navigate = navigate;
    _drain();
  }

  void detach(Future<void> Function(AlertPush) navigate) {
    if (_navigate != navigate) return;
    _navigate = null;
    foreground = null;
    notice = null;
  }

  void _drain() {
    if (_disposed ||
        !_ready ||
        _uid == null ||
        _navigate == null ||
        _pending.isEmpty) {
      return;
    }
    while (_pending.isNotEmpty) {
      final push = _pending.removeFirst();
      if (push.recipientFirebaseUid != _uid) {
        for (final key in _keys(push)) {
          _reserved.remove(key);
        }
        _rejectAccount();
        continue;
      }
      if (push.expired(_now())) {
        notice = 'Cette alerte a expiré. Le signalement peut ne plus être disponible.';
        notifyListeners();
        continue;
      }
      unawaited(_navigatePush(push, _generation, ++_attempt, _navigate!));
    }
  }

  Future<void> _navigatePush(
    AlertPush push,
    int generation,
    int attempt,
    Future<void> Function(AlertPush) navigate,
  ) async {
    try {
      await navigate(push);
      if (!_disposed && generation == _generation && _ready) {
        _remember(_opened, push);
        for (final key in _keys(push)) {
          _reserved.remove(key);
        }
      }
    } catch (error) {
      if (!_disposed &&
          _ready &&
          generation == _generation &&
          attempt == _attempt &&
          _navigate == navigate) {
        _failed = error is AlertOpenFailure && !error.retryable ? null : push;
        notice = error is AlertOpenFailure ? error.message : 'Impossible de cadrer la carte. Réessayez ou consultez l’historique.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_openedSubscription?.cancel());
    _pending.clear();
    super.dispose();
  }
}

/// HTTP recovery and camera/navigation recovery have different user messages.
class AlertOpenFailure implements Exception {
  const AlertOpenFailure(this.message, {this.retryable = true});
  final String message;
  final bool retryable;
}
