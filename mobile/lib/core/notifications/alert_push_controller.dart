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
  Future<void> Function(AlertPush)? _navigate;
  AlertPush? foreground;
  String? notice;
  String? _uid;
  bool _sessionKnown = false;
  bool _started = false;
  bool _disposed = false;
  bool _navigating = false;
  bool _ready = false;
  void setReady(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    if (ready) scheduleMicrotask(_drain);
  }

  int _generation = 0;

  void setSession(String? uid) {
    if (_sessionKnown && _uid != uid) {
      _generation++;
      _pending.clear();
      _displayed.clear();
      _opened.clear();
      foreground = null;
      notice = null;
      _navigate = null;
      _navigating = false;
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
    final keys = [
      'alert:${push.alert.id}',
      'event:${push.alert.eventKey}',
      if (push.messageId != null) 'message:${push.messageId}',
    ];
    if (keys.any(seen.containsKey)) return false;
    for (final key in keys) {
      seen[key] = push.expiresAt;
    }
    while (seen.length > 1536) {
      seen.remove(seen.keys.first);
    }
    return true;
  }

  void open(AlertPush push) {
    if (_disposed) return;
    if (push.expired(_now())) {
      notice =
          'Cette alerte a expiré. Le signalement peut ne plus être disponible.';
      notifyListeners();
      return;
    }
    if (!_remember(_opened, push)) return;
    if (_pending.length == 32) _pending.removeFirst();
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

  Future<void> _drain() async {
    if (_navigating ||
        _disposed ||
        !_ready ||
        _uid == null ||
        _navigate == null ||
        _pending.isEmpty) {
      return;
    }
    final generation = _generation;
    final push = _pending.removeFirst();
    if (push.expired(_now())) {
      notice =
          'Cette alerte a expiré. Le signalement peut ne plus être disponible.';
      notifyListeners();
      _drain();
      return;
    }
    _navigating = true;
    try {
      await _navigate!(push);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        notice = 'Impossible d’ouvrir cette alerte. Consultez l’historique.';
        notifyListeners();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _navigating = false;
        _drain();
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
