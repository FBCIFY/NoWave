import 'dart:convert';
import 'dart:io';

import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/alerts/support/alert_fixtures.dart';

void main() {
  test('le payload du worker ouvre le signalement une seule fois', () async {
    final data = jsonDecode(
      File('../backend/tests/fixtures/alert_push.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final source = FakeAlertPushSource();
    final opened = <AlertPush>[];
    final controller = AlertPushController(
      source: source,
      now: () => DateTime.utc(2026, 10, 13, 13),
    );
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });
    controller.setSession('recipient');
    controller.setReady(true);
    controller.attach((push) async => opened.add(push));
    await controller.start();
    source.taps.add(RemoteMessage(messageId: 'first-attempt', data: data));
    await Future<void>.delayed(Duration.zero);
    source.taps.add(RemoteMessage(messageId: 'after-restart', data: data));
    await Future<void>.delayed(Duration.zero);
    expect(opened, hasLength(1));
    expect(opened.single.alert.id, data['alert_id']);
    expect(opened.single.alert.reportId, data['report_id']);
    expect(opened.single.alert.longitude, 5.4);
    expect(opened.single.alert.latitude, 43.31);
    expect(opened.single.alert.distanceM, 1000);
  });
}
