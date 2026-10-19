import 'dart:async';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/notifications/alert_push_controller.dart';
import 'package:blueway/features/alerts/presentation/alert_report_screen.dart';
import 'package:blueway/features/home/presentation/home_screen.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:geolocator/geolocator.dart' as geo;

import '../../map/support/focus_fakes.dart';
import '../support/alert_fixtures.dart';

class _Reports extends Fake implements ReportDetailService {
  final calls = <String>[];
  Future<ReportDetail> Function(String)? load;
  @override
  Future<ReportDetail> fetchReport(String id) {
    calls.add(id);
    return load?.call(id) ??
        Future.value(focusReport(id: id, longitude: 6, latitude: 44));
  }
}

class _UnavailableGps extends geo.GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

void focusTestWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(
    description,
    body,
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}

void main() {
  late geo.GeolocatorPlatform previousGps;
  late FakeAlertPushSource source;
  late AlertPushController push;
  late _Reports reports;
  late FocusMap map;
  setUp(() {
    previousGps = geo.GeolocatorPlatform.instance;
    geo.GeolocatorPlatform.instance = _UnavailableGps();
    source = FakeAlertPushSource();
    push = AlertPushController(source: source, now: () => testNow);
    reports = _Reports();
    map = FocusMap();
  });
  tearDown(() async {
    geo.GeolocatorPlatform.instance = previousGps;
    push.dispose();
    await source.close();
  });

  MapFocusController selection(WidgetTester tester) =>
      tester.widget<MapScreen>(find.byType(MapScreen)).focusController!;

  Future<void> mount(WidgetTester tester) async {
    push.setSession('user-a');
    push.setReady(true);
    await push.start();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(pushController: push, reportDetailService: reports),
      ),
    );
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onMapCreated!(map);
    tester
        .widget<mb.MapWidget>(find.byType(mb.MapWidget))
        .onStyleLoadedListener!(
      mb.StyleLoadedEventData.fromJson({
        'timeInterval': {'begin': 0, 'end': 1},
      }),
    );
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  for (final delivery in ['foreground', 'background', 'terminated']) {
    focusTestWidgets(
      '$delivery : carte directe, point API, aucun écran ni fiche préalable',
      (tester) async {
        if (delivery == 'terminated') source.initial = pushMessage();
        await mount(tester);
        final original = tester.state(find.byType(MapScreen));
        if (delivery == 'foreground') {
          source.messages.add(pushMessage());
          await tester.pumpAndSettle();
          expect(reports.calls, isEmpty);
          expect(find.text('Ouvrir'), findsOneWidget);
          await tester.tap(find.text('Ouvrir'));
        } else if (delivery == 'background') {
          source.taps.add(pushMessage());
        }
        await tester.pumpAndSettle();
        expect(reports.calls, ['report-a']);
        expect(selection(tester).report!.longitude, 6);
        expect(selection(tester).report!.latitude, 44);
        expect(map.cameras.single.center!.coordinates.lng, 6);
        expect(map.cameras.single.center!.coordinates.lat, 44);
        expect(
          find.byType(AlertReportScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ReportDetailSheet, skipOffstage: false),
          findsNothing,
        );
        expect(tester.state(find.byType(MapScreen)), same(original));
        source.taps.add(pushMessage());
        await tester.pumpAndSettle();
        expect(reports.calls, hasLength(1));
        source.taps.add(pushMessage(id: 'b', reportId: 'report-b'));
        await tester.pumpAndSettle();
        expect(reports.calls, ['report-a', 'report-b']);
        expect(selection(tester).report!.id, 'report-b');
        expect(find.byType(MapScreen, skipOffstage: false), findsOneWidget);
        expect(
          Navigator.of(tester.element(find.byType(MapScreen))).canPop(),
          false,
        );
      },
    );
  }

  focusTestWidgets(
    'panne HTTP puis Réessayer : aucun cadrage inventé, nouvelle lecture API',
    (tester) async {
      reports.load = (_) async => throw TimeoutException('offline');
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de charger'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(selection(tester).report, isNull);
      expect(map.cameras, isEmpty);
      reports.load = null;
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(reports.calls, hasLength(1));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a', 'report-a']);
      expect(map.cameras, hasLength(1));
      expect(find.byType(AlertReportScreen), findsNothing);
    },
  );

  focusTestWidgets(
    'échec de cadrage puis Réessayer : nouvelle lecture et même carte',
    (tester) async {
      map.style.failSelection = true;
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de cadrer'), findsOneWidget);
      expect(map.cameras, isEmpty);
      map.style.failSelection = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a', 'report-a']);
      expect(map.cameras, hasLength(1));
    },
  );

  for (final failure in ['404', 'expired', 'forbidden']) {
    focusTestWidgets(
      '$failure : aucune sélection ni caméra sur un signalement indisponible',
      (tester) async {
        reports.load = (id) async {
          if (failure == '404') {
            throw const ReportNotFoundException();
          }
          if (failure == 'forbidden') {
            throw const ApiException(statusCode: 403, body: '');
          }
          return focusReport(
            id: id,
            expires: DateTime.now().subtract(const Duration(seconds: 1)),
          );
        };
        await mount(tester);
        source.taps.add(pushMessage());
        await tester.pumpAndSettle();
        expect(push.canRetry, false);
        expect(selection(tester).report, isNull);
        expect(map.cameras, isEmpty);
        expect(find.byType(AlertReportScreen), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  }

  focusTestWidgets(
    'brouillon ouvert : diffère la lecture et le cadrage jusqu’à sa fermeture',
    (tester) async {
      await mount(tester);
      final focus = selection(tester);
      focus.setBlocked(true);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Terminez ou annulez'), findsOneWidget);
      expect(focus.isBlocked, true);
      expect(reports.calls, isEmpty);
      expect(map.cameras, isEmpty);
      focus.setBlocked(false);
      await tester.pumpAndSettle();
      expect(reports.calls, ['report-a']);
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets(
    'réponse HTTP ancienne après nouvel événement : conserve la dernière sélection',
    (tester) async {
      final old = Completer<ReportDetail>();
      reports.load = (id) => id == 'report-a'
          ? old.future
          : Future.value(focusReport(id: id, longitude: 7));
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      source.taps.add(pushMessage(id: 'b', reportId: 'report-b'));
      await tester.pumpAndSettle();
      old.complete(focusReport());
      await tester.pumpAndSettle();
      expect(selection(tester).report!.id, 'report-b');
      expect(map.cameras, hasLength(1));
      expect(map.cameras.single.center!.coordinates.lng, 7);
    },
  );

  focusTestWidgets(
    'session suspendue pendant HTTP : abandonne la réponse et la caméra',
    (tester) async {
      final pending = Completer<ReportDetail>();
      reports.load = (_) => pending.future;
      await mount(tester);
      source.taps.add(pushMessage());
      await tester.pumpAndSettle();
      push.setReady(false);
      pending.complete(focusReport());
      await tester.pumpAndSettle();
      expect(selection(tester).report, isNull);
      expect(map.cameras, isEmpty);
      expect(push.canRetry, false);
    },
  );
}
