import 'dart:async';

import 'package:blueway/features/alerts/data/alert_read_store.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/data/unread_alert_recovery.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:blueway/features/map/presentation/map_focus_controller.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../map/support/focus_fakes.dart';
import '../support/alert_fixtures.dart';

class _History extends Fake implements AlertService {
  List<Alert> items = [];
  Future<AlertPage> Function()? load;
  @override
  Future<AlertPage> fetchPage({int page = 1, int limit = 20}) async =>
      load != null
      ? await load!()
      : AlertPage(
          items: items,
          page: page,
          limit: limit,
          total: items.length,
          pages: items.isEmpty ? 0 : 1,
        );
}

class _Reports extends Fake implements ReportDetailService {
  int calls = 0;
  Future<ReportDetail> Function(String)? load;
  @override
  Future<ReportDetail> fetchReport(String id) async {
    calls++;
    return load != null
        ? await load!(id)
        : focusReport(id: id, expires: DateTime.utc(2030));
  }
}

void main() {
  late _History history;
  late _Reports reports;
  late List<MapSonarTarget> received;
  late DateTime now;
  late bool allowed;

  UnreadAlertRecovery create() => UnreadAlertRecovery(
    alerts: history,
    reports: reports,
    readStore: AlertReadStore(accountId: 'a'),
    onUnread: received.add,
    canReceive: () => allowed,
    now: () => now,
  );

  Alert event({int version = 1, DateTime? at}) => Alert.fromJson({
    ...alertJson(version: version),
    'alerted_at': (at ?? now.subtract(const Duration(minutes: 1)))
        .toIso8601String(),
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    history = _History();
    reports = _Reports();
    received = [];
    now = DateTime.utc(2026, 10, 22, 12);
    allowed = true;
  });

  testWidgets('le retour au premier plan récupère sans push ni appui', (
    tester,
  ) async {
    final recovery = create()..start();
    await tester.pump();
    recovery.pause();
    history.items = [event()];
    await tester.pump(const Duration(seconds: 20));
    expect(received, isEmpty);
    recovery.start();
    await tester.pump();
    expect(received.single.id, 'report-a');
    expect(received.single.longitude, 5.373);
    expect(reports.calls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(received, hasLength(1));
    expect(reports.calls, 1);
    recovery.dispose();
  });

  testWidgets('au premier plan une alerte manquée est rattrapée', (
    tester,
  ) async {
    final recovery = create()..start();
    await tester.pump();
    history.items = [event()];
    await tester.pump(const Duration(seconds: 15));
    expect(received.single.id, 'report-a');
    recovery.dispose();
  });

  testWidgets('un détail lu ne relance pas le sonar après redémarrage', (
    tester,
  ) async {
    history.items = [event()];
    final first = create()..start();
    await tester.pump();
    expect(received, hasLength(1));
    await first.markOpened('report-a');
    first.dispose();
    final next = create()..start();
    await tester.pump();
    expect(received, hasLength(1));
    now = now.add(const Duration(minutes: 2));
    history.items = [event(version: 2, at: now)];
    await next.refresh();
    expect(received, hasLength(2));
    next.dispose();
  });

  testWidgets(
    'la réception du push reste immédiate et ne charge pas le détail',
    (tester) async {
      final recovery = create()..start();
      await tester.pump();
      await recovery.receive(
        AlertPush.fromData(pushData(expiry: DateTime.utc(2030))),
      );
      expect(received.single.id, 'report-a');
      expect(reports.calls, 0);
      recovery.dispose();
    },
  );

  testWidgets('une réponse reçue en arrière-plan attend la reprise', (
    tester,
  ) async {
    final pending = Completer<ReportDetail>();
    history.items = [event()];
    reports.load = (_) => pending.future;
    final recovery = create()..start();
    await tester.pump();
    recovery.pause();
    pending.complete(focusReport(expires: DateTime.utc(2030)));
    await tester.pump();
    expect(received, isEmpty);
    recovery.start();
    await tester.pump();
    expect(received, hasLength(1));
    recovery.dispose();
  });

  testWidgets(
    'une session bloquée ou un report expiré ne produit pas de sonar',
    (tester) async {
      history.items = [event()];
      allowed = false;
      final recovery = create()..start();
      await tester.pump();
      expect(reports.calls, 0);
      allowed = true;
      reports.load = (_) async =>
          focusReport(expires: now.subtract(const Duration(seconds: 1)));
      await recovery.refresh();
      expect(received, isEmpty);
      recovery.dispose();
    },
  );
}
