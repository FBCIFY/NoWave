import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Consultations locales de ce compte, conservées quand l'app redémarre.
class AlertReadStore {
  AlertReadStore({
    required String accountId,
    Future<SharedPreferences> Function()? preferences,
  }) : _key = 'alert_report_opened.$accountId',
       _preferences = preferences ?? SharedPreferences.getInstance;

  final String _key;
  final Future<SharedPreferences> Function() _preferences;
  Future<void> _writing = Future.value();

  Future<Map<String, DateTime>> read() async {
    final preferences = await _preferences();
    final json = preferences.getString(_key);
    if (json == null) return {};
    final values = jsonDecode(json) as Map<String, dynamic>;
    return values.map(
      (id, date) => MapEntry(id, DateTime.parse(date as String)),
    );
  }

  Future<void> markOpened(String reportId, DateTime openedAt) {
    return _writing = _writing.catchError((Object _) {}).then((_) async {
      final values = await read();
      final previous = values[reportId];
      if (previous == null || previous.isBefore(openedAt)) {
        values[reportId] = openedAt;
      }
      final recent = values.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final preferences = await _preferences();
      await preferences.setString(
        _key,
        jsonEncode({
          for (final entry in recent.take(256))
            entry.key: entry.value.toUtc().toIso8601String(),
        }),
      );
    });
  }
}
