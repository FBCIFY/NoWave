import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nowave_map_poc/main.dart';
import 'package:nowave_map_poc/map_style.dart';

void main() {
  final uri = Uri.parse('http://localhost/style.json');
  Map<String, dynamic> style(String? mode) => {
    'version': 8,
    'sources': <String, dynamic>{},
    'layers': <dynamic>[],
    'metadata': {'nowave:data_mode': mode},
    'center': [1.2, 3.4],
    'zoom': 12,
  };
  test('Provenance is mandatory before rendering', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode(style(null)), 200),
    );
    await expectLater(MapStyle.load(client, uri), throwsFormatException);
    client.close();
  });
  test('Demo and supplied data retain their provenance and camera', () async {
    for (final mode in ['DEMO_FICTIVE', 'DONNEES_FOURNIES']) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(style(mode)), 200),
      );
      final loaded = await MapStyle.load(client, uri);
      expect(loaded.isDemo, mode == 'DEMO_FICTIVE');
      expect(loaded.longitude, 1.2);
      expect(loaded.latitude, 3.4);
      expect(loaded.zoom, 12);
      client.close();
    }
  });
  test('HTTP failures surface rather than displaying an empty map', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    await expectLater(MapStyle.load(client, uri), throwsStateError);
    client.close();
  });
  testWidgets('Unavailable server offers a working retry', (tester) async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      return http.Response('unavailable', 503);
    });
    await tester.pumpWidget(MaterialApp(home: MapPocScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 503'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    client.close();
  });
}
