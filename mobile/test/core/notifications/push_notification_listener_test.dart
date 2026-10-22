import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/core/notifications/alert_notification_banner.dart';
import 'package:blueway/core/notifications/push_notification_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/alerts/support/alert_fixtures.dart';

void main() {
  testWidgets('foreground : catégorie et distance puis action Ouvrir unique', (
    tester,
  ) async {
    final source = FakeAlertPushSource();
    final controller = AlertPushController(source: source, now: () => testNow);
    addTearDown(() async {
      controller.dispose();
      await source.close();
    });
    controller.setSession('user-a');
    controller.setReady(true);
    await controller.start();
    final opened = <String>[];
    final received = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PushNotificationListener(
          controller: controller,
          onOpen: (push) async => opened.add(push.alert.reportId),
          onReceived: (push) => received.add(push.alert.reportId),
          child: const Scaffold(body: Text('Accueil')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    source.messages.add(pushMessage());
    source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    expect(find.textContaining('Pollution · 1,8 NM'), findsOneWidget);
    expect(find.textContaining('43° 17′ 24″ N'), findsNothing);
    expect(find.text('Nouvelle alerte'), findsNothing);
    final messageCenter = tester.getCenter(find.text('Pollution · 1,8 NM'));
    expect(tester.getCenter(find.text('Ouvrir')).dy, messageCenter.dy);
    expect(
      tester.getCenter(find.byTooltip('Masquer la notification')).dy,
      messageCenter.dy,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getTopLeft(find.byType(AlertNotificationBanner)).dy, 8);
    expect(opened, isEmpty);
    expect(received, ['report-a']);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
    source.taps.add(pushMessage());
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<
    ({
      FakeAlertPushSource source,
      AlertPushController controller,
      List<String> opened,
    })
  >
  mount(
    WidgetTester tester, {
    VoidCallback? onHistory,
    bool accessible = false,
  }) async {
    final source = FakeAlertPushSource();
    final controller = AlertPushController(source: source, now: () => testNow);
    controller.setSession('user-a');
    controller.setReady(true);
    await controller.start();
    final opened = <String>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await source.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 44),
            accessibleNavigation: accessible,
          ),
          child: child!,
        ),
        home: PushNotificationListener(
          controller: controller,
          onOpen: (push) async => opened.add(push.alert.reportId),
          onOpenHistory: onHistory,
          child: const Scaffold(body: Text('Carte')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (source: source, controller: controller, opened: opened);
  }

  testWidgets('bannière sous la zone sûre, dernière alerte seulement', (
    tester,
  ) async {
    final f = await mount(tester);
    f.source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(AlertNotificationBanner)).dy, 52);
    f.source.messages.add(pushMessage(id: 'b', reportId: 'report-b'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertNotificationBanner), findsOneWidget);
    await tester.tap(find.textContaining('Pollution · 1,8 NM'));
    await tester.pumpAndSettle();
    expect(f.opened, ['report-b']);
    expect(find.byType(AlertNotificationBanner), findsNothing);
  });

  testWidgets('masquer ou attendre ferme la bannière sans ouvrir la carte', (
    tester,
  ) async {
    final f = await mount(tester);
    f.source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Masquer la notification'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertNotificationBanner), findsNothing);
    f.source.messages.add(pushMessage(id: 'b', reportId: 'report-b'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.byType(AlertNotificationBanner), findsNothing);
    expect(f.opened, isEmpty);
  });

  testWidgets('alerte expirée : message et historique restent en haut', (
    tester,
  ) async {
    var history = 0;
    final f = await mount(tester, onHistory: () => history++);
    f.source.taps.add(
      pushMessage(expiry: testNow.subtract(const Duration(minutes: 1))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cette alerte a expiré'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AlertNotificationBanner)).dy, 52);
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(history, 1);
    expect(f.opened, isEmpty);
  });

  testWidgets('accessibilité : la bannière attend une action explicite', (
    tester,
  ) async {
    final f = await mount(tester, accessible: true);
    f.source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(AlertNotificationBanner), findsOneWidget);
    f.controller.setSession('user-b');
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(f.opened, isEmpty);
  });

  testWidgets('la bannière apparaît aussi au-dessus d’un autre écran', (
    tester,
  ) async {
    final f = await mount(tester);
    final navigator = Navigator.of(tester.element(find.text('Carte')));
    final pushed = navigator.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Profil'))),
    );
    await tester.pumpAndSettle();
    f.source.messages.add(pushMessage());
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.byType(AlertNotificationBanner), findsOneWidget);
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(f.opened, ['report-a']);
    navigator.pop();
    await pushed;
    await tester.pumpAndSettle();
  });
}
