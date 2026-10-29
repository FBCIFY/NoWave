import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../features/map/data/marine_viewport_test.dart' show ViewMap, harbour;

void main() {
  test('measured harbour selection and warm viewport CPU, no timing assertions', () async {
    for (final size in [10, 100, 1000]) {
      final features = [for (var i = 0; i < size; i++) harbour('port-$i')];
      final pixels = [
        for (var i = 0; i < size; i++)
          ScreenCoordinate(x: (i % 40) * 40.0, y: (i ~/ 40) * 40.0),
      ];
      final times = <int>[];
      for (var trial = 0; trial < 3; trial++) {
        final selection = HarbourSelection();
        for (var warm = 0; warm < 3; warm++) {
          selection.select(features, pixels, 13, 2000, 2000);
        }
        final watch = Stopwatch()..start();
        for (var repeat = 0; repeat < 20; repeat++) {
          expect(
            selection.select(features, pixels, 13, 2000, 2000).length,
            size,
          );
        }
        times.add(watch.elapsedMicroseconds ~/ 20);
      }
      // ignore: avoid_print
      print(
        'MAP_DATA_BENCHMARK ${jsonEncode({'kind': 'ports', 'count': size, 'us_per_selection': times})}',
      );
    }
    final map = ViewMap()..zoom = 13;
    final body = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (var i = 0; i < 1000; i++)
          {
            ...harbour('line-$i'),
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (var j = 0; j < 20; j++)
                  [5.92 + j * .001, 43.08 + i * .000001],
              ],
            },
          },
      ],
    });
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://controlled.example',
      clientFactory: () => MockClient(
        (request) async => http.Response(
          request.url.path.contains('depth-contours')
              ? body
              : '{"type":"FeatureCollection","features":[]}',
          200,
        ),
      ),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    final times = <int>[];
    for (var trial = 0; trial < 3; trial++) {
      final watch = Stopwatch()..start();
      for (var repeat = 0; repeat < 10; repeat++) {
        await viewport.synchronize(map);
      }
      times.add(watch.elapsedMicroseconds ~/ 10);
    }
    expect(viewport.features('depth-contours').length, 1000);
    // ignore: avoid_print
    print(
      'MAP_DATA_BENCHMARK ${jsonEncode({'kind': 'warm_viewport', 'features': 1000, 'coordinates': 20000, 'us_per_sync': times, 'camera_reads': map.cameraReads, 'requests': viewport.requests})}',
    );
  });
}
