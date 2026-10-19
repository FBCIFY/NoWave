import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../reports/domain/report_detail.dart';

/// One selection on the existing map; a superseding request releases its waiter.
class MapFocusController extends ChangeNotifier {
  ReportDetail? _report;
  bool _blocked = false;
  bool includeUserPosition = false;
  int revision = 0;
  Completer<void>? _completion;
  Completer<void>? _unblocked;
  bool Function()? _isCurrent;

  ReportDetail? get report => _report;
  bool get isBlocked => _blocked;
  Future<void> get whenUnblocked => _unblocked?.future ?? Future<void>.value();

  void setBlocked(bool blocked) {
    if (_blocked == blocked) return;
    _blocked = blocked;
    if (blocked) {
      _unblocked ??= Completer<void>();
    } else {
      _unblocked?.complete();
      _unblocked = null;
    }
    notifyListeners();
  }

  /// The history's explicit “show on map” action retains its existing contract.
  bool focus(ReportDetail report) {
    if (_blocked) return false;
    _select(report, includeUser: false);
    return true;
  }

  Future<void> focusAlert(ReportDetail report, {bool Function()? isCurrent}) {
    if (_blocked) throw const MapFocusBlocked();
    final completion = Completer<void>();
    _select(
      report,
      includeUser: true,
      completion: completion,
      isCurrent: isCurrent,
    );
    return completion.future;
  }

  void _select(
    ReportDetail report, {
    required bool includeUser,
    Completer<void>? completion,
    bool Function()? isCurrent,
  }) {
    _finish();
    _report = report;
    _isCurrent = isCurrent;
    includeUserPosition = includeUser;
    _completion = completion;
    revision++;
    notifyListeners();
  }

  void clear() {
    _finish();
    _report = null;
    _isCurrent = null;
    revision++;
    notifyListeners();
  }

  void complete(int request) {
    if (request == revision) _finish();
  }

  bool isCurrent(int request) =>
      request == revision && (_isCurrent?.call() ?? true);

  bool fail(int request, Object error) {
    if (request != revision) return false;
    final completion = _completion;
    _completion = null;
    completion?.completeError(error);
    return completion != null;
  }

  void _finish() {
    _completion?.complete();
    _completion = null;
  }

  @override
  void dispose() {
    _finish();
    _unblocked?.complete();
    _unblocked = null;
    super.dispose();
  }
}

class MapFocusBlocked implements Exception {
  const MapFocusBlocked();
}
