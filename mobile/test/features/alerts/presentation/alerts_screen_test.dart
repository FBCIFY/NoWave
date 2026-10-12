import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/presentation/alerts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/alert_fixtures.dart';

void main() {
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];
  final opened = <String>[];
  setUp(() {
    requests.clear();
    opened.clear();
  });
  Future<void> open(WidgetTester tester) async {
    final client = MockClient((request) {
      requests.add(request);
      return respond(request);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          service: AlertService(
            apiService: ApiService(
              client: client,
              baseUrl: 'https://nowave.test/',
            ),
            getIdToken: () async => 'test-token',
          ),
          onOpen: (alert) async => opened.add(alert.reportId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('historique vide sans état lu/non lu', (tester) async {
    respond = (_) async =>
        http.Response(jsonEncode(pageJson(items: [], pages: 0, total: 0)), 200);
    await open(tester);
    expect(find.text('Aucune alerte pour le moment.'), findsOneWidget);
    expect(find.text('Charger la suite'), findsNothing);
  });
  testWidgets('catégorie distance position et ouverture détail', (
    tester,
  ) async {
    respond = (_) async => http.Response(jsonEncode(pageJson()), 200);
    await open(tester);
    expect(find.text('Pollution'), findsOneWidget);
    expect(find.textContaining('1,8 NM'), findsOneWidget);
    expect(find.textContaining('43° 17′ 24″ N'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert-a')));
    await tester.pumpAndSettle();
    expect(opened, ['report-a']);
  });
  testWidgets('plusieurs pages et retry page suivante', (tester) async {
    respond = (_) async =>
        http.Response(jsonEncode(pageJson(pages: 2, total: 21)), 200);
    await open(tester);
    respond = (_) async => http.Response('', 503);
    await tester.tap(find.text('Charger la suite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hors ligne'), findsOneWidget);
    expect(find.text('Pollution'), findsOneWidget);
    respond = (_) async => http.Response(
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
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.url.queryParameters['page']), ['1', '2', '2']);
    expect(find.text('Pollution'), findsNWidgets(2));
    expect(find.text('Charger la suite'), findsNothing);
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
}
