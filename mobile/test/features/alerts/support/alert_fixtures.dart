import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/notifications/alert_push_source.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final testNow = DateTime.utc(2026, 10, 10, 10);
Map<String, dynamic> alertJson({
  String id = 'alert-a',
  String reportId = 'report-a',
  int version = 1,
}) => {
  'id': id,
  'report_id': reportId,
  'report_version': version,
  'category': 'pollution',
  'position': {
    'type': 'Point',
    'coordinates': [5.37, 43.29],
  },
  'distance_m': 3334.0,
  'alerted_at': '2026-10-10T09:00:00Z',
};
Alert alert({
  String id = 'alert-a',
  String reportId = 'report-a',
  int version = 1,
}) => Alert.fromJson(alertJson(id: id, reportId: reportId, version: version));
Map<String, dynamic> pageJson({
  List<Map<String, dynamic>>? items,
  int page = 1,
  int pages = 1,
  int total = 1,
}) => {
  'items': items ?? [alertJson()],
  'page': page,
  'limit': 20,
  'total': total,
  'pages': pages,
};
Map<String, dynamic> pushData({
  String id = 'alert-a',
  String reportId = 'report-a',
  int version = 1,
  DateTime? expiry,
}) => {
  'alert_id': id,
  'report_id': reportId,
  'report_version': '$version',
  'category': 'pollution',
  'position': jsonEncode({
    'type': 'Point',
    'coordinates': [5.37, 43.29],
  }),
  'position_dms': '43° 17′ 24″ N · 5° 22′ 12″ E',
  'distance_m': '3334.0',
  'alerted_at': '2026-10-10T09:00:00Z',
  'expires_at': (expiry ?? testNow.add(const Duration(hours: 1)))
      .toIso8601String(),
};
RemoteMessage pushMessage({
  String id = 'alert-a',
  String reportId = 'report-a',
  int version = 1,
  String? messageId,
  DateTime? expiry,
}) => RemoteMessage(
  messageId: messageId ?? 'message-$id',
  data: pushData(id: id, reportId: reportId, version: version, expiry: expiry),
);

class FakeAlertPushSource implements AlertPushSource {
  final messages = StreamController<RemoteMessage>.broadcast(sync: true);
  final taps = StreamController<RemoteMessage>.broadcast(sync: true);
  RemoteMessage? initial;
  Future<RemoteMessage?>? delayedInitial;
  int initialCalls = 0;
  @override
  Stream<RemoteMessage> get foreground => messages.stream;
  @override
  Stream<RemoteMessage> get opened => taps.stream;
  @override
  Future<RemoteMessage?> initialMessage() async {
    initialCalls++;
    return delayedInitial ?? initial;
  }

  Future<void> close() async {
    await messages.close();
    await taps.close();
  }
}
