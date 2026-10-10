import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/core/notifications/push_notification_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/alerts/support/alert_fixtures.dart';

void main() {
  testWidgets('foreground : catégorie DMS distance puis action Ouvrir unique', (
    tester,
  ) async {
    final source = FakeAlertPushSource();
    final controller = AlertPushController(source: source, now: () => testNow);
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });
    controller.setSession('user');
    controller.setReady(true);
    await controller.start();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PushNotificationListener(
          controller: controller,
          onOpen: (push) async => opened.add(push.alert.reportId),
          child: const Scaffold(body: Text('Accueil')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    source.messages.add(pushMessage());
    source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    expect(find.textContaining('Pollution · 1,8 NM'), findsOneWidget);
    expect(find.textContaining('43° 17′ 24″ N'), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
    source.taps.add(pushMessage());
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
