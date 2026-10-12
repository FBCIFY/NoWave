import 'package:flutter/foundation.dart';

import '../domain/alert.dart';
import 'alert_service.dart';

/// Pagination sans cache persistant : une panne ne signifie pas « vide ».
class AlertHistoryController extends ChangeNotifier {
  AlertHistoryController(this.service);
  final AlertService service;
  final List<Alert> _items = [];
  List<Alert> get items => List.unmodifiable(_items);
  bool loading = false;
  bool loaded = false;
  Object? error;
  int page = 0;
  int pages = 0;
  int total = 0;
  bool _disposed = false;
  bool _failedRefresh = false;
  Future<void> retry() => load(refresh: _failedRefresh);
  bool get hasMore => loaded && page < pages;

  Future<void> load({bool refresh = false}) async {
    if (loading || (!refresh && loaded && !hasMore)) return;
    _failedRefresh = refresh;
    loading = true;
    error = null;
    notifyListeners();
    final target = refresh ? 1 : page + 1;
    try {
      final result = await service.fetchPage(page: target);
      if (_disposed) return;
      if (refresh) _items.clear();
      final ids = _items.map((a) => a.id).toSet();
      final events = _items.map((a) => a.eventKey).toSet();
      for (final alert in result.items) {
        if (!ids.contains(alert.id) && !events.contains(alert.eventKey)) {
          _items.add(alert);
          ids.add(alert.id);
          events.add(alert.eventKey);
        }
      }
      page = result.page;
      pages = result.pages;
      total = result.total;
      loaded = true;
    } catch (e) {
      if (!_disposed) error = e;
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
