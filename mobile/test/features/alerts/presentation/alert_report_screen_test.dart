import 'dart:async';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:blueway/features/alerts/presentation/alert_report_screen.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/alert_fixtures.dart';
import '../../map/support/focus_fakes.dart' show focusPosition;

class _Location extends LocationService {
  bool allowed = true;
  late final result = Completer<Position>();
  int requests = 0;
  @override
  Future<bool> canWatchPosition() async => allowed;
  @override
  Future<Position> getCurrentPosition() {
    requests++;
    return result.future;
  }
}

ReportDetail report({DateTime? expiry}) => ReportDetail(
  id: 'report-a',
  category: ReportCategory.pollution,
  description: 'Position actualisée',
  latitude: 44,
  longitude: 6,
  observedAt: testNow.subtract(const Duration(hours: 1)),
  expiresAt: expiry ?? testNow.add(const Duration(hours: 1)),
  author: null,
  boat: null,
  photo: null,
);

class Reports extends Fake implements ReportDetailService {
  late Future<ReportDetail> Function() respond;
  final ids = <String>[];
  @override
  Future<ReportDetail> fetchReport(String id) {
    ids.add(id);
    return respond();
  }
}

void main() {
  late Reports service;
  late _Location location;
  setUp(() {
    service = Reports();
    location = _Location();
  });
  Future<void> open(
    WidgetTester tester, {
    Future<void> Function(ReportDetail)? onMap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertReportScreen(
          reportId: 'report-a',
          service: service,
          locationService: location,
          now: () => testNow,
          onShowOnMap: onMap ?? (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'la position GPS arrivée après le détail met à jour la distance',
    (tester) async {
      service.respond = () async => report();
      await open(tester);
      expect(find.text('Votre position est inconnue'), findsOneWidget);
      location.result.complete(focusPosition());
      await tester.pumpAndSettle();
      expect(find.text('Votre position est inconnue'), findsNothing);
      expect(find.textContaining(' NM au '), findsOneWidget);
      expect(service.ids, ['report-a']);
    },
  );

  testWidgets('GPS refusé : fiche disponible sans demander de position', (
    tester,
  ) async {
    location.allowed = false;
    service.respond = () async => report();
    await open(tester);
    expect(location.requests, 0);
    expect(find.text('Votre position est inconnue'), findsOneWidget);
    expect(find.text('Voir sur la carte'), findsOneWidget);
  });

  testWidgets('GPS en échec : conserve la fiche et le repli sans position', (
    tester,
  ) async {
    service.respond = () async => report();
    await open(tester);
    location.result.completeError(StateError('GPS indisponible'));
    await tester.pumpAndSettle();
    expect(find.text('Votre position est inconnue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relit le détail puis utilise la position actuelle pour la carte',
    (tester) async {
      service.respond = () async => report();
      ReportDetail? selection;
      await open(tester, onMap: (r) async => selection = r);
      expect(service.ids, ['report-a']);
      expect(find.text('Position actualisée'), findsOneWidget);
      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();
      expect(selection!.longitude, 6);
      expect(selection!.latitude, 44);
    },
  );
  testWidgets(
    'Voir sur la carte délègue au callback sans créer une seconde MapScreen',
    (tester) async {
      service.respond = () async => report();
      var navigations = 0;

      await open(
        tester,
        onMap: (_) async {
          navigations++;
        },
      );

      await tester.tap(find.text('Voir sur la carte'));
      await tester.pumpAndSettle();

      expect(navigations, 1);
      expect(find.byType(MapScreen), findsNothing);
    },
  );
  testWidgets('signalement expiré malgré HTTP 200 ne propose aucune carte', (
    tester,
  ) async {
    service.respond = () async => report(expiry: testNow);
    await open(tester);
    expect(find.textContaining('n’est plus disponible'), findsOneWidget);
    expect(find.text('Voir sur la carte'), findsNothing);
  });
  for (final error in <Object>[
    const ReportNotFoundException(),
    const ApiException(statusCode: 401, body: ''),
    const ApiException(statusCode: 403, body: ''),
    const ApiException(statusCode: 503, body: ''),
    TimeoutException('timeout'),
    http.ClientException('offline'),
  ]) {
    testWidgets('report indisponible : $error', (tester) async {
      service.respond = () async => throw error;
      await open(tester);
      expect(find.text('Voir sur la carte'), findsNothing);
      if (error is ReportNotFoundException) {
        expect(find.textContaining('n’est plus disponible'), findsOneWidget);
      } else {
        expect(find.text('Réessayer'), findsOneWidget);
        service.respond = () async => report();
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();
        expect(find.text('Voir sur la carte'), findsOneWidget);
      }
    });
  }
  testWidgets('signalement retiré entre détail et carte : aucune navigation', (
    tester,
  ) async {
    service.respond = () async => report();
    var navigations = 0;
    await open(
      tester,
      onMap: (_) async {
        navigations++;
      },
    );
    service.respond = () async => throw const ReportNotFoundException();
    await tester.tap(find.text('Voir sur la carte'));
    await tester.pumpAndSettle();
    expect(navigations, 0);
    expect(service.ids, ['report-a', 'report-a']);
    expect(find.text('Ce signalement n’est plus disponible.'), findsOneWidget);
  });

  testWidgets('double appui carte ne double pas la navigation', (tester) async {
    service.respond = () async => report();
    final route = Completer<void>();
    var count = 0;
    await open(
      tester,
      onMap: (_) {
        count++;
        return route.future;
      },
    );
    await tester.tap(find.text('Voir sur la carte'));
    await tester.tap(find.text('Voir sur la carte'));
    await tester.pump();
    expect(count, 1);
    route.complete();
    await tester.pumpAndSettle();
  });
}
