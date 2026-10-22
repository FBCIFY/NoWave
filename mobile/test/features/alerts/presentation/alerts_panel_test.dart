import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/alerts/data/alert_history_controller.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/presentation/alerts_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/alert_fixtures.dart';

void main() {
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];
  final opened = <String>[];
  var closed = 0;
  setUp(() {
    requests.clear();
    opened.clear();
    closed = 0;
  });
  Future<void> open(
    WidgetTester tester, {
    ({double latitude, double longitude})? userPosition,
  }) async {
    final client = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    addTearDown(client.close);
    final history = AlertHistoryController(
      AlertService(
        apiService: ApiService(client: client, baseUrl: 'https://nowave.test/'),
        getIdToken: () async => 'test-token',
      ),
    )..load();
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AlertsPanel(
                  history: history,
                  onOpen: (alert) => opened.add(alert.reportId),
                  onClose: () => closed++,
                  userPosition: userPosition,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('historique vide sans état lu/non lu', (tester) async {
    respond = (_) async =>
        http.Response(jsonEncode(pageJson(items: [], pages: 0, total: 0)), 200);
    await open(tester);
    expect(find.text('Mes alertes'), findsOneWidget);
    expect(find.text('Aucune alerte pour le moment.'), findsOneWidget);
    expect(requests, hasLength(1));
  });

  testWidgets('catégorie, distance lors de l’alerte et ouverture de la fiche', (
    tester,
  ) async {
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    await open(tester);
    expect(find.text('Pollution'), findsOneWidget);
    expect(find.textContaining('1,8 NM lors de l’alerte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert-a')));
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
  });

  testWidgets('position connue : distance actuelle au signalement', (
    tester,
  ) async {
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    // Une minute d'arc au nord du signalement : 1 NM, au lieu des 1,8 NM
    // mesurés lors de l'alerte.
    await open(
      tester,
      userPosition: (latitude: 43.29 + 1 / 60, longitude: 5.37),
    );
    expect(find.textContaining('lors de l’alerte'), findsNothing);
    expect(find.textContaining('1,0 NM'), findsOneWidget);
  });

  testWidgets('la page suivante arrive seule, puis retry après une panne', (
    tester,
  ) async {
    var page2Fails = true;
    respond = (request) async {
      if (request.url.queryParameters['page'] == '1') {
        return http.Response(jsonEncode(pageJson(pages: 2, total: 21)), 200);
      }
      if (page2Fails) return http.Response('', 503);
      return http.Response(
        jsonEncode(
          pageJson(
            page: 2,
            pages: 2,
            total: 21,
            items: [alertJson(id: 'b', reportId: 'b')],
          ),
        ),
        200,
      );
    };
    await open(tester);
    expect(find.textContaining('hors ligne'), findsOneWidget);
    expect(find.text('Pollution'), findsOneWidget);
    page2Fails = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.url.queryParameters['page']), ['1', '2', '2']);
    expect(find.text('Pollution'), findsNWidgets(2));
    expect(find.text('Réessayer'), findsNothing);
  });

  for (final status in [401, 403, 404, 500]) {
    testWidgets('HTTP $status affiche une erreur puis retry', (tester) async {
      respond = (_) async => http.Response('', status);
      await open(tester);
      expect(find.text('Aucune alerte pour le moment.'), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
      respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Pollution'), findsOneWidget);
    });
  }

  testWidgets('hors réseau puis retour connexion avec retry', (tester) async {
    respond = (_) async => throw http.ClientException('offline');
    await open(tester);
    expect(find.textContaining('hors ligne'), findsOneWidget);
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Pollution'), findsOneWidget);
  });

  testWidgets('actualiser recharge la première page', (tester) async {
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    await open(tester);
    await tester.tap(find.byTooltip('Actualiser les alertes'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.url.queryParameters['page']), ['1', '1']);
    expect(find.text('Pollution'), findsOneWidget);
  });

  testWidgets('croix ou poignée glissée vers le bas : fermeture', (
    tester,
  ) async {
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    await open(tester);
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester);
    await tester.fling(
      find.byKey(const ValueKey('map-panel-drag-handle')),
      const Offset(0, 120),
      1000,
    );
    await tester.pumpAndSettle();
    expect(closed, 2);
  });

  testWidgets('jamais plus de la moitié de l’écran', (tester) async {
    respond = (request) async => http.Response(
      jsonEncode(
        pageJson(
          items: [
            for (var i = 0; i < 20; i++)
              alertJson(id: 'alert-$i', reportId: 'report-$i'),
          ],
        ),
      ),
      200,
    );
    await open(tester);
    final screen = tester.getSize(find.byType(Scaffold)).height;
    expect(
      tester.getSize(find.byType(AlertsPanel)).height,
      lessThanOrEqualTo(screen / 2),
    );
  });
}
