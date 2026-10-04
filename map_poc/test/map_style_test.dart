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
    'metadata': {
      'nowave:data_mode': mode,
      'nowave:relief_label': 'réel Mapzen/AWS (externe)',
    },
    'center': [1.2, 3.4],
    'zoom': 12,
  };
  test('Provenance is mandatory before rendering', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(style(null)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await expectLater(MapStyle.load(client, uri), throwsFormatException);
    client.close();
  });
  test('Demo and supplied data retain their provenance and camera', () async {
    for (final mode in ['DEMO_FICTIVE', 'DONNEES_FOURNIES', 'REGION_REAL']) {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(style(mode)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final loaded = await MapStyle.load(client, uri);
      expect(loaded.isDemo, mode == 'DEMO_FICTIVE');
      expect(loaded.longitude, 1.2);
      expect(loaded.latitude, 3.4);
      expect(loaded.zoom, 12);
      client.close();
    }
  });
  test('Banner separates real DEM and fictitious nautical data', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(style('DEMO_FICTIVE')),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final loaded = await MapStyle.load(client, uri);
    expect(loaded.bannerText, contains('réel Mapzen/AWS (externe)'));
    expect(loaded.bannerText, contains('Bathymétrie = fictive'));
    expect(loaded.bannerText, contains('objets nautiques = fictifs'));
    client.close();
  });
  test('Real terrain preview has no depth legend or nautical claims', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(style('RELIEF_REAL_PREVIEW')),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final loaded = await MapStyle.load(client, uri);
    expect(loaded.isReliefPreview, isTrue);
    expect(loaded.bannerText, contains('sans bathymétrie'));
    expect(loaded.bannerText, contains('non affichés ici'));
    client.close();
  });
  test('Cassis banner identifies real sources and missing depths', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(style('CASSIS_REAL')),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final loaded = await MapStyle.load(client, uri);
    expect(loaded.isDemo, isFalse);
    expect(loaded.isCassisReal, isTrue);
    expect(loaded.bannerText, contains('Côte = réelle OSM'));
    expect(loaded.bannerText, contains('Bathymétrie = réelle SHOM'));
    expect(loaded.bannerText, contains('profondeur indisponible'));
    expect(loaded.bannerText, contains('navigation officielle'));
    client.close();
  });
  test('HTTP failures surface rather than displaying an empty map', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    await expectLater(MapStyle.load(client, uri), throwsStateError);
    client.close();
  });
  test(
    'Regional HTTPS style retains the same endpoints for native clients',
    () async {
      const base = 'https://maps.nowave.example';
      final regional = style('REGION_REAL')
        ..['glyphs'] = '$base/assets/font/{fontstack}/{range}.pbf'
        ..['sprite'] = '$base/assets/sprite'
        ..['sources'] = {
          'features': {
            'type': 'vector',
            'tiles': ['$base/tiles/vector/france_med/{z}/{x}/{y}.pbf'],
          },
          'bathymetry': {
            'type': 'raster',
            'tiles': ['$base/tiles/bathymetry/france_med/{z}/{x}/{y}.png'],
          },
          'water': {
            'type': 'geojson',
            'data': '$base/data/france_med/water.geojson',
          },
        };
      final client = MockClient((request) async {
        expect(request.url, Uri.parse('$base/style.json'));
        return http.Response(
          jsonEncode(regional),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final loaded = await MapStyle.load(client, Uri.parse('$base/style.json'));
      expect(loaded.isDemo, isFalse);
      expect(jsonDecode(loaded.json), regional);
      client.close();
    },
  );
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
