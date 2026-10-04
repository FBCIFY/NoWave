import 'dart:convert';
import 'dart:math' as math;

import 'package:blueway/core/map/map_config.dart';
import 'package:blueway/core/map/map_controller.dart';
import 'package:blueway/core/map/map_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('URL configurable : LAN, simulateur, HTTPS ; aucun jeton requis', () {
    for (final url in [
      'http://192.168.1.50:8765/style.json',
      'http://127.0.0.1:8765/style.json',
      'http://10.0.2.2:8765/style.json',
      'https://cartes.example.org/style.json',
    ]) {
      expect(MapConfig.styleUri(url, production: false).toString(), url);
    }
    for (final url in [
      '',
      'mapbox://styles/mapbox/standard',
      'file:///style.json',
    ]) {
      expect(
        () => MapConfig.styleUri(url, production: false),
        throwsFormatException,
      );
    }
    expect(
      () => MapConfig.styleUri(
        'http://192.168.1.50/style.json',
        production: true,
      ),
      throwsFormatException,
    );
    expect(
      MapConfig.styleUri(
        'https://cartes.example.org/style.json',
        production: true,
      ).scheme,
      'https',
    );
  });
  test(
    'charge le vrai style et conserve toutes les URLs accessibles au téléphone',
    () async {
      const base = 'http://192.168.1.50:8765';
      final client = MockClient((request) async {
        expect(request.url.toString(), '$base/style.json');
        return http.Response(
          jsonEncode({
            'version': 8,
            'metadata': {'nowave:data_mode': 'REGION_REAL'},
            'sources': {
              'vector': {
                'type': 'vector',
                'tiles': ['$base/tiles/{z}/{x}/{y}.pbf'],
              },
              'raster': {
                'type': 'raster',
                'tiles': ['$base/raster/{z}/{x}/{y}.png'],
              },
              'water': {'type': 'geojson', 'data': '$base/water.geojson'},
            },
            'sprite': '$base/assets/sprite',
            'glyphs': '$base/assets/{fontstack}/{range}.pbf',
            'layers': [],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final style = jsonDecode(
        await NoWaveMapStyle.load(client, '$base/style.json'),
      ) as Map;
      expect(style['glyphs'], startsWith(base));
      expect(style['sprite'], startsWith(base));
      expect(style['sources']['water']['data'], startsWith(base));
      expect(style['sources']['raster']['tiles'][0], startsWith(base));
      expect(style['sources']['vector']['tiles'][0], startsWith(base));
    },
  );
  test('propage HTTP, JSON invalide et données fictives', () async {
    for (final response in [
      http.Response('indisponible', 503),
      http.Response('{}', 200),
      http.Response(
        jsonEncode({
          'version': 8,
          'sources': {},
          'layers': [],
          'metadata': {'nowave:data_mode': 'DEMO_FICTIVE'},
        }),
        200,
      ),
    ]) {
      final client = MockClient((_) async => response);
      await expectLater(
        NoWaveMapStyle.load(client, 'https://cartes.example.org/style.json'),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
      client.close();
    }
  });
  test('pointe du marqueur au centre du viewport malgré le panneau', () {
    final padding = paddingForMarker(
      const Offset(195, 250),
      const Size(390, 844),
    );
    expect(padding, const EdgeInsets.only(bottom: 344));
    expect(
      Offset(
        (390 + padding.left - padding.right) / 2,
        (844 + padding.top - padding.bottom) / 2,
      ),
      const Offset(195, 250),
    );
  });
  test('projection réversible Android haute densité et iOS en points', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final units = MapProjectionUnits(platform: platform, pixelRatio: 3);
      const tip = Offset(195, 250);
      final native = units.toNative(tip);
      expect(
        native,
        platform == TargetPlatform.android
            ? const math.Point(585.0, 750.0)
            : const math.Point(195.0, 250.0),
      );
      expect(units.toFlutter(native), tip);
    }
  });
}
