import 'dart:async';

import 'package:blueway/features/alerts/data/alert_history_controller.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/alert_fixtures.dart';

class FakeAlerts extends Fake implements AlertService {
  final requests = <int>[];
  late Future<AlertPage> Function(int) respond;
  @override
  Future<AlertPage> fetchPage({int page = 1, int limit = 20}) {
    requests.add(page);
    return respond(page);
  }
}

void main() {
  late FakeAlerts service;
  late AlertHistoryController controller;
  setUp(() {
    service = FakeAlerts();
    controller = AlertHistoryController(service);
  });
  tearDown(() => controller.dispose());

  test(
    'plusieurs pages, déduplication id/report-version, fin de pagination',
    () async {
      service.respond = (page) async => AlertPage.fromJson(
        pageJson(
          page: page,
          pages: 2,
          total: 3,
          items: page == 1
              ? [alertJson()]
              : [
                  alertJson(),
                  alertJson(id: 'other-id'),
                  alertJson(id: 'a2', reportId: 'r2'),
                ],
        ),
      );
      await controller.load();
      expect(controller.hasMore, isTrue);
      await controller.load();
      await controller.load();
      expect(service.requests, [1, 2]);
      expect(controller.items, hasLength(2));
      expect(controller.hasMore, isFalse);
    },
  );
  test('erreur page suivante puis retry conserve page et liste', () async {
    service.respond = (_) async =>
        AlertPage.fromJson(pageJson(pages: 2, total: 21));
    await controller.load();
    service.respond = (_) async => throw TimeoutException('offline');
    await controller.load();
    expect(controller.page, 1);
    expect(controller.items, hasLength(1));
    expect(controller.error, isA<TimeoutException>());
    service.respond = (p) async => AlertPage.fromJson(
      pageJson(
        page: p,
        pages: 2,
        total: 21,
        items: [alertJson(id: 'a2', reportId: 'r2')],
      ),
    );
    await controller.retry();
    expect(service.requests, [1, 2, 2]);
    expect(controller.items, hasLength(2));
  });
  test(
    'refresh échoué en dernière page puis retry remplace les anciennes données',
    () async {
      service.respond = (_) async => AlertPage.fromJson(pageJson());
      await controller.load();
      service.respond = (_) async => throw StateError('offline');
      await controller.load(refresh: true);
      expect(controller.items, hasLength(1));
      service.respond = (_) async =>
          AlertPage.fromJson(pageJson(items: [], pages: 0, total: 0));
      await controller.retry();
      expect(controller.items, isEmpty);
      expect(service.requests, [1, 1, 1]);
    },
  );
  test('requêtes concurrentes ne doublent pas une page', () async {
    final pending = Completer<AlertPage>();
    service.respond = (_) => pending.future;
    final load = controller.load();
    await controller.load();
    pending.complete(AlertPage.fromJson(pageJson()));
    await load;
    expect(service.requests, [1]);
  });
}
