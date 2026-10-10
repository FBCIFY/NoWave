import 'dart:async';

import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/alerts/support/alert_fixtures.dart';

void main() {
  late FakeAlertPushSource source;
  late AlertPushController controller;
  late DateTime now;
  final opened = <AlertPush>[];
  Future<void> navigate(AlertPush push) async {
    opened.add(push);
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() {
    source = FakeAlertPushSource();
    now = testNow;
    opened.clear();
    controller = AlertPushController(source: source, now: () => now);
  });
  tearDown(() async {
    controller.dispose();
    await source.close();
  });

  Future<void> ready() async {
    controller.setSession('user-a');
    controller.setReady(true);
    controller.attach(navigate);
    await controller.start();
  }

  test('foreground affiche une fois, aucun déplacement avant appui', () async {
    await ready();
    var notices = 0;
    controller.addListener(() => notices++);
    source.messages.add(pushMessage());
    source.messages.add(pushMessage());
    expect(notices, 1);
    expect(opened, isEmpty);
    final push = controller.foreground!;
    controller.open(push);
    controller.open(push);
    await flush();
    expect(opened, hasLength(1));
  });
  test(
    'background : tap et doublon initial naviguent une seule fois',
    () async {
      source.initial = pushMessage();
      await ready();
      source.taps.add(pushMessage());
      await flush();
      expect(opened, hasLength(1));
      expect(source.initialCalls, 1);
      await controller.start();
      expect(source.initialCalls, 1);
    },
  );
  test(
    'terminated simulé : conserve le tap avant session/profil prêt',
    () async {
      source.initial = pushMessage();
      await controller.start();
      controller.attach(navigate);
      expect(opened, isEmpty);
      controller.setSession('user-a');
      controller.setReady(true);
      await flush();
      expect(opened.single.alert.reportId, 'report-a');
    },
  );
  test(
    'même événement avec identifiants de transport différents est dédupliqué',
    () async {
      await ready();
      source.taps.add(pushMessage());
      source.taps.add(pushMessage(id: 'other-id', messageId: 'other-message'));
      await flush();
      expect(opened, hasLength(1));
      source.taps.add(pushMessage(id: 'version-2', version: 2));
      await flush();
      expect(opened, hasLength(2));
    },
  );
  test(
    'même messageId ou alertId ne provoque pas une autre navigation',
    () async {
      await ready();
      source.taps.add(pushMessage(messageId: 'shared'));
      source.taps.add(pushMessage(id: 'b', reportId: 'b', messageId: 'shared'));
      source.taps.add(pushMessage(reportId: 'c', messageId: 'different'));
      await flush();
      expect(opened, hasLength(1));
    },
  );
  test(
    'deux événements distincts attendent la fermeture de la première route',
    () async {
      final route = Completer<void>();
      controller.setSession('user-a');
      controller.setReady(true);
      controller.attach((push) {
        opened.add(push);
        return route.future;
      });
      await controller.start();
      source.taps.add(pushMessage());
      source.taps.add(pushMessage(id: 'b', reportId: 'b'));
      expect(opened, hasLength(1));
      route.complete();
      await flush();
      expect(opened, hasLength(2));
    },
  );
  test('expiration à réception et pendant attente ne navigue pas', () async {
    await ready();
    source.taps.add(pushMessage(expiry: now));
    expect(opened, isEmpty);
    expect(controller.notice, contains('expiré'));
    controller.setReady(false);
    source.taps.add(pushMessage());
    now = now.add(const Duration(hours: 2));
    controller.setReady(true);
    await flush();
    expect(opened, isEmpty);
  });
  test('payload invalide ou incomplet ne crashe pas', () async {
    await ready();
    source.taps.add(const RemoteMessage(data: {'report_id': 'a'}));
    source.messages.add(const RemoteMessage(data: {}));
    expect(opened, isEmpty);
    expect(controller.notice, contains('invalide'));
  });
  test('panne source signalée, historique reste le recours', () async {
    await ready();
    source.taps.addError(StateError('offline'));
    expect(controller.notice, contains('historique'));
    expect(opened, isEmpty);
  });
  test('erreur initiale interceptée', () async {
    source.delayedInitial = Future.error(StateError('SDK indisponible'));
    await controller.start();
    expect(controller.notice, contains('indisponibles'));
  });
  test(
    'logout abandonne événements et reprise tardive de getInitialMessage',
    () async {
      final initial = Completer<RemoteMessage?>();
      source.delayedInitial = initial.future;
      controller.setSession('user-a');
      final start = controller.start();
      source.taps.add(pushMessage());
      controller.setSession(null);
      controller.setSession('user-b');
      controller.setReady(true);
      controller.attach(navigate);
      initial.complete(pushMessage());
      await start;
      await flush();
      expect(opened, isEmpty);
      expect(controller.foreground, isNull);
    },
  );
  test(
    'détachement de l’ancien accueil ne détache pas le nouvel accueil',
    () async {
      await ready();
      Future<void> other(AlertPush push) async {
        opened.add(push);
      }

      controller.attach(other);
      controller.detach(navigate);
      source.taps.add(pushMessage());
      await flush();
      expect(opened, hasLength(1));
    },
  );
  test(
    'profil suspendu ou déconnexion : aucune ouverture avant réautorisation',
    () async {
      await ready();
      controller.setReady(false);
      source.taps.add(pushMessage());
      source.messages.add(pushMessage(id: 'fg', reportId: 'fg'));
      expect(opened, isEmpty);
      expect(controller.foreground, isNull);
      controller.setReady(true);
      await flush();
      expect(opened, hasLength(1));
    },
  );
  test(
    'le callback de navigation échoué donne un message et reste dédupliqué',
    () async {
      await ready();
      controller.attach((_) async => throw StateError('navigation'));
      source.taps.add(pushMessage());
      await flush();
      expect(controller.notice, contains('Impossible'));
      controller.attach(navigate);
      source.taps.add(pushMessage());
      await flush();
      expect(opened, isEmpty);
    },
  );
}
