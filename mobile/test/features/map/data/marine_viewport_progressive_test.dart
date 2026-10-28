import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_cell.dart';
import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'marine_viewport_test.dart' show ViewMap, until;

MarineCell requestedCell(http.Request r) {
  final p = r.url.pathSegments;
  return MarineCell(
    int.parse(p[5]),
    int.parse(p[6]),
    int.parse(p[7].split('.').first),
  );
}

http.Response response(
  List<Map<String, dynamic>> features, {
  String status = 'ok',
}) => http.Response(
  jsonEncode({'type': 'FeatureCollection', 'features': features}),
  200,
  headers: {'x-nowave-marine-status': status},
);

Map<String, dynamic> pointIn(MarineCell c, String id) => {
  'type': 'Feature',
  'id': id,
  'geometry': {
    'type': 'Point',
    'coordinates': [(c.west + c.east) / 2, (c.south + c.north) / 2],
  },
  'properties': {'name': id, 'category': 'harbour'},
};

class BoundsMap extends ViewMap {
  CoordinateBounds? bounds;
  @override
  Future<CoordinateBounds> coordinateBoundsForCamera(
    CameraOptions options,
  ) async => bounds ?? await super.coordinateBoundsForCamera(options);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'wide pitched bounds load all visible cells before margin with two workers',
    () async {
      final map = BoundsMap()..zoom = 9;
      final center = MarineCell.at(map.longitude, 43.08, 9);
      final topLeft = MarineCell(9, center.x - 2, center.y - 2);
      final bottomRight = MarineCell(9, center.x + 1, center.y + 1);
      map.bounds = CoordinateBounds(
        southwest: Point(
          coordinates: Position(
            topLeft.west + .000001,
            bottomRight.south + .000001,
          ),
        ),
        northeast: Point(
          coordinates: Position(
            bottomRight.east - .000001,
            topLeft.north - .000001,
          ),
        ),
        infiniteBounds: false,
      );
      final seen = <MarineCell>[];
      var active = 0, peak = 0;
      final viewport = MarineViewport(
        apiBaseUrl: 'https://controlled.example',
        viewportSize: () => const ui.Size(1024, 768),
        clientFactory: () => MockClient((request) async {
          final cell = requestedCell(request);
          seen.add(cell);
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          return response([pointIn(cell, cell.key)]);
        }),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      final visible = MarineCellRange(map.bounds!, 9);
      expect(visible.count, 16);
      expect(seen, hasLength(36));
      expect(seen.first.key, center.key);
      expect(seen.take(16).every(visible.contains), isTrue);
      expect(seen.skip(16).any(visible.contains), isFalse);
      expect(viewport.features('harbours'), hasLength(36));
      expect(peak, 2);
      expect(viewport.metrics['active'], 0);
      final before = viewport.requests;
      await viewport.synchronize(map);
      expect(viewport.requests, before);
    },
  );

  test(
    'families alternate at the centre before loading their borders',
    () async {
      final map = ViewMap()..zoom = 12;
      final families = <String>[];
      final viewport = MarineViewport(
        apiBaseUrl: 'https://controlled.example',
        viewportSize: () => const ui.Size(360, 805),
        clientFactory: () => MockClient((r) async {
          families.add(r.url.pathSegments[4]);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return response([]);
        }),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      expect(families.take(5), MarineViewport.sources.keys);
      expect(viewport.requests, 45);
    },
  );

  test('one detailed point appears before a sibling finishes; empty removes only its covered old point', () async {
    final map = BoundsMap()..zoom = 12;
    final parent = MarineCell.at(map.longitude, 43.08, 12);
    final children = parent.children.toList();
    final oldPoints = [for (final c in children) pointIn(c, 'old-${c.key}')];
    map.bounds = CoordinateBounds(
      southwest: Point(
        coordinates: Position(parent.west + .000001, parent.south + .000001),
      ),
      northeast: Point(
        coordinates: Position(parent.east - .000001, parent.north - .000001),
      ),
      infiniteBounds: false,
    );
    final pending = <String, Completer<http.Response>>{};
    final viewport = MarineViewport(
      apiBaseUrl: 'https://controlled.example',
      viewportSize: () => const ui.Size(360, 805),
      clientFactory: () => MockClient((r) async {
        final c = requestedCell(r);
        if (r.url.pathSegments[4] != 'harbours') return response([]);
        if (c.z == 12) return response(c.key == parent.key ? oldPoints : []);
        return (pending[c.key] = Completer<http.Response>()).future;
      }),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    expect(viewport.features('harbours'), hasLength(4));
    map.zoom = 13;
    final loading = viewport.synchronize(map);
    await until(() => pending.length >= 2);
    final first = pending.keys.first;
    final cell = children.firstWhere((c) => c.key == first);
    pending[first]!.complete(response([pointIn(cell, 'new-detail')]));
    await until(
      () => viewport.features('harbours').any((f) => f['id'] == 'new-detail'),
    );
    final ids = viewport.features('harbours').map((f) => f['id']).toSet();
    expect(ids, contains('new-detail'));
    expect(ids, isNot(contains('old-$first')));
    expect(ids.where((id) => id.toString().startsWith('old-')), hasLength(3));
    // All remaining child responses are valid empty cells. Drain without any
    // gesture so a sibling cannot hold the first replacement hostage.
    var done = false;
    unawaited(
      loading.then((_) {
        done = true;
      }),
    );
    while (!done) {
      for (final p in pending.values.toList()) {
        if (!p.isCompleted) p.complete(response([]));
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await loading;
    expect(viewport.features('harbours').map((f) => f['id']), ['new-detail']);
  });

  test('large minimum-resolution demand stays bounded and does not redownload deferred cells', () async {
    final map = BoundsMap()..zoom = 14;
    map.bounds = CoordinateBounds(
      southwest: Point(coordinates: Position(-180, -85)),
      northeast: Point(coordinates: Position(180, 85)),
      infiniteBounds: false,
    );
    final viewport = MarineViewport(
      apiBaseUrl: 'https://controlled.example',
      viewportSize: () => const ui.Size(1024, 768),
      clientFactory: () => MockClient((_) async => response([])),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    expect(viewport.metrics['planned_visible'] as int, greaterThan(64));
    expect(viewport.metrics['wanted'], 64);
    expect(viewport.metrics['cache_entries'], lessThanOrEqualTo(64));
    expect(viewport.requests, 64);
    await viewport.synchronize(map);
    expect(viewport.requests, 64);
    final levels = viewport.metrics['request_zooms'] as Map;
    expect(levels['depth-contours'], 12);
    expect(levels['soundings'], 12);
    expect(levels['harbours'], 6);
  });

  test('unwrapped antimeridian bounds retain old surfaces when the next zoom fails', () async {
    final map = BoundsMap()
      ..zoom = 12
      ..longitude = 179.99;
    map.bounds = CoordinateBounds(
      southwest: Point(coordinates: Position(179.99, 43.07999)),
      northeast: Point(coordinates: Position(180.01, 43.08001)),
      infiniteBounds: false,
    );
    final surface = <String, dynamic>{
      'type': 'Feature',
      'id': 'across-dateline',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [-179.999, 43.08],
            [-179.995, 43.08],
            [-179.995, 43.080005],
            [-179.999, 43.080005],
            [-179.999, 43.08],
          ],
        ],
      },
      'properties': <String, dynamic>{},
    };
    final viewport = MarineViewport(
      apiBaseUrl: 'https://controlled.example',
      viewportSize: () => const ui.Size(360, 805),
      clientFactory: () => MockClient((r) async {
        final c = requestedCell(r);
        if (c.z == 13) return http.Response('{}', 503);
        return response(
          r.url.pathSegments[4] == 'underwater-hazards' &&
                  c.contains(-179.999, 43.08)
              ? [surface]
              : [],
        );
      }),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    expect(
      viewport.features('underwater-hazards').map((f) => f['id']),
      contains('across-dateline'),
    );
    map.zoom = 13;
    await viewport.synchronize(map);
    expect(
      viewport.features('underwater-hazards').map((f) => f['id']),
      contains('across-dateline'),
    );
    expect(viewport.errors, greaterThan(0));
  });

  test(
    'valid empty refresh clears retained points and canonical contours',
    () async {
      final map = ViewMap()..zoom = 12;
      var now = DateTime.utc(2026, 10, 27);
      var empty = false;
      final viewport = MarineViewport(
        apiBaseUrl: 'https://controlled.example',
        viewportSize: () => const ui.Size(360, 805),
        now: () => now,
        clientFactory: () => MockClient((r) async {
          if (empty) return response([], status: 'empty');
          final c = requestedCell(r);
          if (!c.contains(map.longitude, 43.08)) return response([]);
          final feature = pointIn(c, 'published');
          if (r.url.pathSegments[4] == 'depth-contours') {
            feature['geometry'] = {
              'type': 'LineString',
              'coordinates': [
                [map.longitude, 43.08],
                [map.longitude + .00001, 43.08],
              ],
            };
          }
          return response([feature]);
        }),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      expect(viewport.features('harbours'), hasLength(1));
      expect(viewport.features('depth-contours'), hasLength(1));
      empty = true;
      now = now.add(const Duration(seconds: 301));
      await viewport.synchronize(map);
      expect(viewport.features('harbours'), isEmpty);
      expect(viewport.features('depth-contours'), isEmpty);
    },
  );

  test('encoded saturation preserves useful data and does not become a network retry loop', () async {
    final map = ViewMap()..zoom = 12;
    var now = DateTime.utc(2026, 10, 27);
    var dense = true;
    final viewport = MarineViewport(
      apiBaseUrl: 'https://controlled.example',
      viewportSize: () => const ui.Size(360, 805),
      now: () => now,
      clientFactory: () => MockClient((r) async {
        if (!dense) return response([]);
        final c = requestedCell(r);
        final feature = pointIn(c, '${r.url.pathSegments[4]}/${c.key}');
        feature['properties']['payload'] = 'a' * (3 * 1024 * 1024);
        return response([feature]);
      }),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    expect(
      viewport.metrics['cache_encoded_bytes'],
      lessThanOrEqualTo(12 * 1024 * 1024),
    );
    expect(viewport.metrics['budget_deferred'], greaterThan(0));
    expect(viewport.errors, 0);
    final count = viewport.requests;
    now = now.add(const Duration(seconds: 20));
    await viewport.synchronize(map);
    expect(viewport.requests, count);
    expect(viewport.metrics['active'], 0);
    // A successful refresh that frees bytes re-enables deferred cells.
    dense = false;
    now = now.add(const Duration(seconds: 301));
    await viewport.synchronize(map);
    expect(viewport.metrics['budget_deferred'], 0);
    expect(viewport.metrics['cache_entries'], viewport.metrics['wanted']);
  });
}
