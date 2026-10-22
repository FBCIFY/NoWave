import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../map/presentation/map_focus_controller.dart';
import '../../reports/data/report_detail_service.dart';
import '../domain/alert.dart';
import 'alert_read_store.dart';
import 'alert_service.dart';

/// Rattrape les alertes sans dépendre d'un appui sur la notification système.
/// Le serveur fait foi après un retour dans l'app ; le push reste immédiat.
class UnreadAlertRecovery {
  UnreadAlertRecovery({
    required this.alerts,
    required this.reports,
    required this.readStore,
    required this.onUnread,
    required this.canReceive,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AlertService alerts;
  final ReportDetailService reports;
  final AlertReadStore readStore;
  final ValueChanged<MapSonarTarget> onUnread;
  final bool Function() canReceive;
  final DateTime Function() _now;
  final _opened = <String, DateTime>{};
  final _unavailable = <String>{};
  Future<void>? _loadingReads;
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;
  int _revision = 0;
  String? _currentEvent;
  String? _currentReport;
  DateTime? _currentAlertedAt;
  DateTime? _currentExpiry;

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _revision++;
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  Future<void> _loadReads() => _loadingReads ??= () async {
    try {
      final saved = await readStore.read();
      for (final entry in saved.entries) {
        if ((_opened[entry.key]?.isBefore(entry.value) ?? true)) {
          _opened[entry.key] = entry.value;
        }
      }
    } catch (_) {
      // Une panne du stockage local ne doit pas masquer une nouvelle alerte.
    }
  }();

  bool _unread(Alert alert) {
    final openedAt = _opened[alert.reportId];
    return openedAt == null || (alert.alertedAt ?? _now()).isAfter(openedAt);
  }

  bool _current(int revision) =>
      !_disposed && _timer != null && revision == _revision && canReceive();

  void _show(Alert alert, MapSonarTarget target) {
    _currentEvent = alert.eventKey;
    _currentReport = alert.reportId;
    _currentAlertedAt = alert.alertedAt ?? _now();
    _currentExpiry = target.expiresAt;
    onUnread(target);
  }

  Future<void> receive(AlertPush push) async {
    final revision = ++_revision;
    await _loadReads();
    if (!_current(revision) || push.expired(_now()) || !_unread(push.alert)) {
      return;
    }
    if (_currentEvent == push.alert.eventKey &&
        (_currentExpiry?.isAfter(_now()) ?? false)) {
      return;
    }
    _show(push.alert, (
      id: push.alert.reportId,
      latitude: push.alert.latitude,
      longitude: push.alert.longitude,
      category: push.alert.category,
      expiresAt: push.expiresAt,
    ));
  }

  Future<void> markOpened(String reportId) async {
    final openedAt = _now();
    _opened[reportId] = openedAt;
    if (_currentReport == reportId) {
      _currentEvent = null;
      _currentReport = null;
      _currentAlertedAt = null;
      _currentExpiry = null;
    }
    try {
      await readStore.markOpened(reportId, openedAt);
    } catch (_) {
      // L'arrêt du sonar reste effectif dans cette session.
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || _timer == null || !canReceive()) return;
    _refreshing = true;
    final revision = _revision;
    try {
      await _loadReads();
      if (!_current(revision)) return;
      final page = await alerts.fetchPage();
      for (final alert in page.items) {
        if (!_current(revision)) return;
        if (!_unread(alert) || _unavailable.contains(alert.eventKey)) continue;
        if (_currentExpiry?.isAfter(_now()) ?? false) {
          if (_currentEvent == alert.eventKey ||
              (alert.alertedAt?.isBefore(_currentAlertedAt ?? _now()) ??
                  false)) {
            return;
          }
        }
        try {
          final report = await reports.fetchReport(alert.reportId);
          if (!_current(revision)) return;
          if (!_unread(alert)) continue;
          if (report.id != alert.reportId ||
              !report.latitude.isFinite ||
              !report.longitude.isFinite ||
              report.latitude.abs() > 90 ||
              report.longitude.abs() > 180 ||
              !report.expiresAt.isAfter(_now())) {
            _unavailable.add(alert.eventKey);
            continue;
          }
          _show(alert, (
            id: report.id,
            latitude: report.latitude,
            longitude: report.longitude,
            category: report.category,
            expiresAt: report.expiresAt,
          ));
          return;
        } on ReportNotFoundException {
          _unavailable.add(alert.eventKey);
        }
      }
    } catch (_) {
      // Garder le sonar courant si le réseau ou le service est indisponible.
    } finally {
      _refreshing = false;
      if (!_disposed && _timer != null && revision != _revision) {
        unawaited(refresh());
      }
    }
  }
}
