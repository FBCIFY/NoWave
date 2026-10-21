import 'dart:convert';

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Map<String, dynamic> harbour(String id) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [5.93, 43.08],
  },
  'properties': {'name': 'Port $id', 'category': 'harbour'},
};

class ViewStyle extends Fake implements StyleManager {
  final data = <String, String>{};
  @override
  Future<bool> styleSourceExists(String id) async => true;
  @override
  Future<void> setStyleSourceProperty(
    String id,
    String key,
    Object value,
  ) async {
    data[id] = value as String;
  }
}

class ViewMap extends Fake implements MapboxMap {
  double zoom = 6;
  double longitude = 5.93;
  @override
  final ViewStyle style = ViewStyle();
  @override
  Future<CameraState> getCameraState() async => CameraState(
    center: Point(coordinates: Position(longitude, 43.08)),
    padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
    zoom: zoom,
    bearing: 0,
    pitch: 0,
  );
  @override
  Future<CoordinateBounds> coordinateBoundsForCamera(
    CameraOptions options,
  ) async => CoordinateBounds(
    southwest: Point(coordinates: Position(5.8, 43)),
    northeast: Point(coordinates: Position(6, 43.2)),
    infiniteBounds: false,
  );
  @override
  Future<Size> getSize() async => Size(width: 360, height: 805);
  @override
  Future<List<ScreenCoordinate?>> pixelsForCoordinates(
    List<Point> points,
  ) async => [for (final _ in points) ScreenCoordinate(x: 180, y: 400)];
}

void main() {
  test('deterministic Z8 collision winner is retained against earlier-sorting newcomers through Z18', () {
    final selector = HarbourSelection();
    final a = harbour('a'), b = harbour('b'), c = harbour('0');
    List<ScreenCoordinate> positions(double d) => [
      ScreenCoordinate(x: 100, y: 100),
      ScreenCoordinate(x: 100 + d, y: 100),
    ];
    expect(
      selector.select([b, a], positions(0), 8, 360, 805).single['id'],
      'a',
    );
    expect(
      selector
          .select([b, a], positions(100), 9.99, 360, 805)
          .map((f) => f['id']),
      ['a'],
    );
    for (final zoom in [10.0, 12.0, 13.0, 14.0, 15.0, 16.0, 18.0]) {
      final selected = selector.select(
        [c, a, b],
        [
          ScreenCoordinate(x: 100, y: 100),
          ScreenCoordinate(x: 100, y: 100),
          ScreenCoordinate(x: 200, y: 100),
        ],
        zoom,
        360,
        805,
      );
      expect(selected.first['id'], 'a');
      expect(selected.map((f) => f['id']), ['a', 'b']);
    }
    expect(selector.select([a, b], positions(100), 7.99, 360, 805), isEmpty);
    expect(selector.order, isEmpty);
  });

  test('actual downloads at Z6, Z10, Z12; cache reuse and line geometry survives reload/zoom/reverse', () async {
    final seen = <Uri>[];
    var concurrent = 0, peak = 0;
    final map = ViewMap();
    final viewport = MarineViewport(
      apiBaseUrl: 'http://marine.example/proxy?tenant=eu',
      clientFactory: () => MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(
          request.url.path,
          startsWith('/proxy/api/v1/map/marine-features/'),
        );
        expect(request.url.queryParameters['tenant'], 'eu');
        seen.add(request.url);
        concurrent++;
        if (concurrent > peak) peak = concurrent;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        concurrent--;
        final contour = request.url.path.contains('depth-contours');
        final feature = contour
            ? {
                'type': 'Feature',
                'id': 'real-line@12/cell',
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [5.9, 43.08],
                    [6.0, 43.08],
                  ],
                },
                'properties': {
                  'id': 'real-line',
                  'display_minzoom': 12,
                  'value_m': 10,
                },
              }
            : harbour('real-port');
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [feature],
          }),
          200,
        );
      }),
    );
    await viewport.synchronize(map);
    expect(seen.length, 9);
    expect(seen.every((u) => u.path.contains('/harbours/6/')), isTrue);
    expect(jsonDecode(map.style.data['nowave-harbours']!)['features'], isEmpty);
    expect(peak, lessThanOrEqualTo(2));
    await viewport.synchronize(map);
    expect(seen.length, 9);
    map.zoom = 10;
    await viewport.synchronize(map);
    expect(seen.any((u) => u.path.contains('/seamarks/12/')), isTrue);
    expect(seen.any((u) => u.path.contains('/underwater-hazards/12/')), isTrue);
    expect(seen.any((u) => u.path.contains('/depth-contours/')), isFalse);
    for (final source in ['nowave-buoys', 'nowave-underwater-hazards']) {
      expect(jsonDecode(map.style.data[source]!)['features'], isEmpty);
    }
    expect(viewport.features('seamarks'), isNotEmpty);
    final preloadRequests = seen.length;
    map.zoom = 10.5;
    await viewport.synchronize(map);
    expect(seen.length, preloadRequests);
    for (final source in ['nowave-buoys', 'nowave-underwater-hazards']) {
      expect(jsonDecode(map.style.data[source]!)['features'], isNotEmpty);
    }
    map.zoom = 12;
    await viewport.synchronize(map);
    final line = viewport.features('depth-contours').single;
    expect(seen.any((u) => u.path.contains('/soundings/12/')), isTrue);
    final lineRequests = seen
        .where((u) => u.path.contains('/depth-contours/'))
        .length;
    for (final z in [13.0, 14.0, 15.0, 16.0, 18.0, 16.0, 13.0, 12.99]) {
      map.zoom = z;
      await viewport.synchronize(map);
      expect(viewport.features('depth-contours').single, equals(line));
      expect(
        seen.where((u) => u.path.contains('/depth-contours/')).length,
        lineRequests,
      );
    }
    expect(seen.any((u) => u.path.contains('/soundings/16/')), isTrue);
    viewport.styleLoaded();
    map.style.data.clear();
    await viewport.synchronize(map);
    expect(
      jsonDecode(map.style.data['nowave-depth-contours']!)['features'].single,
      equals(line),
    );
    viewport.dispose();
  });

  test(
    'HTTP errors are retried after backoff, never accepted as empty data',
    () async {
      final map = ViewMap();
      final viewport = MarineViewport(
        apiBaseUrl: 'https://marine.example',
        clientFactory: () => MockClient((_) async => http.Response('{}', 503)),
      );
      await viewport.synchronize(map);
      expect(viewport.features('harbours'), isEmpty);
      expect(viewport.metrics['errors'], 9);
      expect(viewport.metrics['cache_entries'], 0);
      await viewport.synchronize(map);
      expect(viewport.metrics['requests'], 9);
      viewport.dispose();
    },
  );
  test(
    'degraded diagnostics stay bounded across pans and clear below preload',
    () async {
      final map = ViewMap();
      final viewport = MarineViewport(
        apiBaseUrl: 'https://marine.example',
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '{"type":"FeatureCollection","features":[]}',
            200,
            headers: {'x-nowave-marine-status': 'degraded'},
          ),
        ),
      );
      addTearDown(viewport.dispose);
      for (final longitude in [5.93, 35.0, 65.0, 95.0]) {
        map.longitude = longitude;
        await viewport.synchronize(map);
        expect((viewport.metrics['last_errors'] as Map).length, 9);
        expect(viewport.metrics['cache_entries'], 9);
      }
      map.zoom = 5;
      await viewport.synchronize(map);
      expect(viewport.metrics['last_errors'], isEmpty);
      expect(viewport.metrics['cache_entries'], 0);
    },
  );
  test('a recovered partial snapshot adds curves while retaining each old geometry', () async {
    var now = DateTime.utc(2026, 10, 21);
    var recovered = false;
    final map = ViewMap()..zoom = 13;
    Map<String, dynamic> curve(String id, double latitude) => {
      'type': 'Feature',
      'id': id,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [5.9, latitude],
          [6.0, latitude],
        ],
      },
      'properties': {'id': id, 'display_minzoom': 12, 'value_m': 10},
    };
    final viewport = MarineViewport(
      apiBaseUrl: 'https://marine.example',
      now: () => now,
      clientFactory: () => MockClient((request) async {
        final contours = request.url.path.contains('depth-contours');
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': contours
                ? [
                    curve('A', recovered ? 43.09 : 43.08),
                    if (recovered) curve('B', 43.07),
                  ]
                : [],
          }),
          200,
          headers: {'x-nowave-marine-status': recovered ? 'ok' : 'degraded'},
        );
      }),
    );
    await viewport.synchronize(map);
    final original = viewport.features('depth-contours').single;
    recovered = true;
    now = now.add(const Duration(seconds: 16));
    await viewport.synchronize(map);
    final result = viewport.features('depth-contours');
    expect(result.map((f) => f['id']).toSet(), {'A', 'B'});
    expect(result.singleWhere((f) => f['id'] == 'A'), original);
    expect(viewport.metrics['last_errors'], isEmpty);
    viewport.pause();
    final requests = viewport.requests;
    await viewport.synchronize(map);
    expect(viewport.requests, requests);
    viewport.resume(map);
    viewport.dispose();
  });
}
