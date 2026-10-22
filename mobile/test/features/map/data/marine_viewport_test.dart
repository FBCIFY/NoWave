import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter/services.dart';
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
  double bearing = 0;
  int cameraReads = 0;
  @override
  final ViewStyle style = ViewStyle();
  @override
  Future<CameraState> getCameraState() async {
    cameraReads++;
    return CameraState(
      center: Point(coordinates: Position(longitude, 43.08)),
      padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      zoom: zoom,
      bearing: bearing,
      pitch: 0,
    );
  }

  @override
  Future<CoordinateBounds> coordinateBoundsForCamera(
    CameraOptions options,
  ) async => CoordinateBounds(
    southwest: Point(coordinates: Position(longitude - .13, 43)),
    northeast: Point(coordinates: Position(longitude + .13, 43.2)),
    infiniteBounds: false,
  );
  @override
  Future<Size> getSize() async => Size(width: 360, height: 805);
  @override
  Future<List<ScreenCoordinate?>> pixelsForCoordinates(
    List<Point> points,
  ) async => [for (final _ in points) ScreenCoordinate(x: 180, y: 400)];
}

class IosViewMap extends ViewMap {
  @override
  Future<Size> getSize() async =>
      throw PlatformException(code: '0', message: 'Not available.');
}

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not reached within two seconds');
}

void main() {
  test('iOS without native getSize publishes every marine source', () async {
    final map = IosViewMap()..zoom = 0;
    var size = const ui.Size(360, 805);
    final viewport = MarineViewport(
      viewportSize: () => size,
      apiBaseUrl: 'https://marine.example/',
      clientFactory: () => MockClient((request) async {
        final family = request.url.pathSegments[4];
        final feature = harbour(family);
        if (family == 'depth-contours') {
          feature['geometry'] = {
            'type': 'LineString',
            'coordinates': [
              [5.9, 43.08],
              [6.0, 43.08],
            ],
          };
        }
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [feature],
          }),
          200,
        );
      }),
    );
    addTearDown(viewport.dispose);

    await viewport.synchronize(map);
    expect(map.style.data.keys, containsAll(MarineViewport.sources.values));

    map.zoom = 13;
    await viewport.synchronize(map);
    for (final source in MarineViewport.sources.values) {
      expect(
        jsonDecode(map.style.data[source]!)['features'],
        isNotEmpty,
        reason: source,
      );
    }

    // Layout can temporarily be empty; this must not block the other layers.
    size = ui.Size.zero;
    await viewport.synchronize(map);
    expect(jsonDecode(map.style.data['nowave-harbours']!)['features'], isEmpty);
    expect(
      jsonDecode(map.style.data['nowave-soundings']!)['features'],
      isNotEmpty,
    );

    // A resize and a native style reload use the new Flutter bounds.
    size = const ui.Size(100, 805);
    await viewport.synchronize(map);
    expect(jsonDecode(map.style.data['nowave-harbours']!)['features'], isEmpty);
    size = const ui.Size(360, 805);
    viewport.styleLoaded();
    map.style.data.clear();
    await viewport.synchronize(map);
    for (final source in MarineViewport.sources.values) {
      expect(
        jsonDecode(map.style.data[source]!)['features'],
        isNotEmpty,
        reason: source,
      );
    }
  });

  test(
    'harbour collisions follow the screen while retaining visible winners',
    () {
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
        ['a', 'b'],
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
    },
  );

  test('rejected port appears after its blocker leaves; rotation, pitch and tile changes recalculate placement', () {
    final selector = HarbourSelection();
    final a = harbour('a'), b = harbour('b'), c = harbour('c');
    List<String> ids(
      List<Map<String, dynamic>> features,
      List<ScreenCoordinate?> pixels,
      double zoom,
    ) => selector
        .select(features, pixels, zoom, 360, 805)
        .map((feature) => feature['id'].toString())
        .toList();
    ScreenCoordinate at(double x, double y) => ScreenCoordinate(x: x, y: y);
    expect(ids([b, a, c], [at(100, 100), at(100, 100), at(100, 100)], 8), [
      'a',
    ]);
    expect(ids([a, b], [at(-100, 100), at(100, 100)], 9), ['b']);
    expect(ids([a, b], [at(100, 100), at(100, 100)], 9), ['b']);
    expect(ids([a, b], [at(100, 100), at(200, 100)], 9), ['b', 'a']);
    expect(ids([a, b, c], [at(100, 100), at(100, 100), at(220, 100)], 9), [
      'b',
      'c',
    ]);
    expect(ids([a, b], [at(100, 100), at(200, 100)], 10), ['b', 'a']);
    expect(ids([a], [at(100, 100)], 9), ['a']);
    expect(ids([b], [at(100, 100)], 9), ['b']);
    expect(ids([a, b], [at(100, 100), at(100, 100)], 7.9), isEmpty);
    expect(ids([a, b], [at(100, 100), at(100, 100)], 8), ['a']);
  });

  test('actual downloads at Z6, Z10, Z12; cache reuse and line geometry survives reload/zoom/reverse', () async {
    final seen = <Uri>[];
    var concurrent = 0, peak = 0;
    final map = ViewMap();
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
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
        viewportSize: () => const ui.Size(360, 805),
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
        viewportSize: () => const ui.Size(360, 805),
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
      viewportSize: () => const ui.Size(360, 805),
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

  for (final marineStatus in ['empty', 'outside-coverage']) {
    test(
      'soundings $marineStatus replaces Z12 coverage and keeps a 300s TTL',
      () async {
        var clock = DateTime.utc(2026, 10, 22);
        final map = ViewMap()..zoom = 12;
        final seen = <Uri>[];
        final oldCell = {
          'type': 'Feature',
          'id': 'modeled-z12',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [5.92, 43.07],
                [5.94, 43.07],
                [5.94, 43.09],
                [5.92, 43.07],
              ],
            ],
          },
          'properties': {'display_minzoom': 12},
        };
        final viewport = MarineViewport(
          viewportSize: () => const ui.Size(360, 805),
          apiBaseUrl: 'https://marine.example',
          now: () => clock,
          clientFactory: () => MockClient((request) async {
            seen.add(request.url);
            final soundings = request.url.path.contains('/soundings/');
            final z12 = request.url.path.contains('/soundings/12/');
            return http.Response(
              jsonEncode({
                'type': 'FeatureCollection',
                'features': z12 ? [oldCell] : [],
              }),
              200,
              headers: {
                'x-nowave-marine-status': soundings && !z12
                    ? marineStatus
                    : 'ok',
              },
            );
          }),
        );
        addTearDown(viewport.dispose);
        await viewport.synchronize(map);
        expect(viewport.features('soundings').single['id'], 'modeled-z12');
        map.zoom = 13;
        await viewport.synchronize(map);
        expect(
          seen.where((uri) => uri.path.contains('/soundings/13/')).length,
          9,
        );
        expect(viewport.features('soundings'), isEmpty);
        expect(
          jsonDecode(map.style.data['nowave-soundings']!)['features'],
          isEmpty,
        );
        expect(viewport.metrics['last_errors'], isEmpty);
        final requests = viewport.requests;
        clock = clock.add(const Duration(seconds: 16));
        await viewport.synchronize(map);
        expect(viewport.requests, requests);
        expect(viewport.metrics['last_errors'], isEmpty);
        clock = clock.add(const Duration(seconds: 283));
        await viewport.synchronize(map);
        expect(viewport.requests, requests);
        clock = clock.add(const Duration(seconds: 2));
        await viewport.synchronize(map);
        expect(viewport.requests, greaterThan(requests));
      },
    );
  }

  for (final marineStatus in ['degraded', 'partial']) {
    test(
      'soundings $marineStatus cannot replace displayed Z12 coverage',
      () async {
        var clock = DateTime.utc(2026, 10, 22);
        final map = ViewMap()..zoom = 12;
        final seen = <Uri>[];
        final viewport = MarineViewport(
          viewportSize: () => const ui.Size(360, 805),
          apiBaseUrl: 'https://marine.example',
          now: () => clock,
          clientFactory: () => MockClient((request) async {
            seen.add(request.url);
            final z12 = request.url.path.contains('/soundings/12/');
            return http.Response(
              jsonEncode({
                'type': 'FeatureCollection',
                'features': z12
                    ? [
                        {
                          'type': 'Feature',
                          'id': 'old-sounding',
                          'geometry': {
                            'type': 'Polygon',
                            'coordinates': [
                              [
                                [5.92, 43.07],
                                [5.94, 43.07],
                                [5.94, 43.09],
                                [5.92, 43.07],
                              ],
                            ],
                          },
                          'properties': {'display_minzoom': 12},
                        },
                      ]
                    : [],
              }),
              200,
              headers: {
                'x-nowave-marine-status':
                    request.url.path.contains('/soundings/13/')
                    ? marineStatus
                    : 'ok',
              },
            );
          }),
        );
        addTearDown(viewport.dispose);
        await viewport.synchronize(map);
        map.zoom = 13;
        await viewport.synchronize(map);
        expect(viewport.features('soundings').single['id'], 'old-sounding');
        expect(
          jsonDecode(
            map.style.data['nowave-soundings']!,
          )['features'].single['id'],
          'old-sounding',
        );
        expect((viewport.metrics['last_errors'] as Map).length, 9);
        expect(
          (viewport.metrics['last_errors'] as Map).values,
          everyElement('degraded'),
        );
        final requests = seen
            .where((uri) => uri.path.contains('/soundings/13/'))
            .length;
        expect(requests, 9);
        clock = clock.add(const Duration(seconds: 16));
        await viewport.synchronize(map);
        expect(
          seen.where((uri) => uri.path.contains('/soundings/13/')).length,
          18,
        );
        expect(viewport.features('soundings').single['id'], 'old-sounding');
      },
    );
  }

  test(
    'non-point coverage survives pending, 503, degraded, Z14 and style reload',
    () async {
      var clock = DateTime.utc(2026, 10, 22);
      final map = ViewMap()..zoom = 12;
      final gate13 = Completer<void>(), gate14 = Completer<void>();
      var mode = 'pending';
      var peak = 0, active = 0;
      Map<String, dynamic> feature(
        String id,
        String type,
        Object coordinates,
      ) => {
        'type': 'Feature',
        'id': id,
        'geometry': {'type': type, 'coordinates': coordinates},
        'properties': {'display_minzoom': 12},
      };
      final shapes = [
        feature('polygon', 'Polygon', [
          [
            [5.92, 43.07],
            [5.94, 43.07],
            [5.94, 43.09],
            [5.92, 43.07],
          ],
        ]),
        feature('multi-polygon', 'MultiPolygon', [
          [
            [
              [5.92, 43.07],
              [5.94, 43.07],
              [5.94, 43.09],
              [5.92, 43.07],
            ],
          ],
        ]),
        feature('line', 'LineString', [
          [5.92, 43.07],
          [5.94, 43.09],
        ]),
        feature('multi-line', 'MultiLineString', [
          [
            [5.92, 43.07],
            [5.94, 43.09],
          ],
        ]),
      ];
      final cell = feature('modeled-cell', 'Polygon', [
        [
          [5.92, 43.07],
          [5.94, 43.07],
          [5.94, 43.09],
          [5.92, 43.07],
        ],
      ]);
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://marine.example',
        now: () => clock,
        clientFactory: () => MockClient((request) async {
          active++;
          if (active > peak) peak = active;
          try {
            final path = request.url.path;
            final hazard = path.contains('underwater-hazards');
            final sounding = path.contains('soundings');
            final z13 = path.contains('/13/'), z14 = path.contains('/14/');
            if ((hazard || sounding) && z13 && mode == 'pending') {
              await gate13.future;
            }
            if ((hazard || sounding) && z14) {
              await gate14.future;
            }
            if ((hazard || sounding) && z13 && mode == 'pending') {
              return http.Response('{}', 503);
            }
            final degraded = z13 && (mode == 'degraded' || mode == 'partial');
            final data = map.longitude > 20 || !(hazard || sounding)
                ? []
                : degraded
                ? [
                    feature('partial', 'Polygon', [
                      [
                        [5.92, 43.07],
                        [5.94, 43.07],
                        [5.94, 43.09],
                        [5.92, 43.07],
                      ],
                    ]),
                  ]
                : hazard
                ? shapes
                      .map(
                        (f) => {
                          ...f,
                          'id':
                              '${f['id']}-z${z14
                                  ? 14
                                  : z13
                                  ? 13
                                  : 12}',
                        },
                      )
                      .toList()
                : [
                    {
                      ...cell,
                      'id':
                          'modeled-cell-z${z14
                              ? 14
                              : z13
                              ? 13
                              : 12}',
                    },
                  ];
            return http.Response(
              jsonEncode({'type': 'FeatureCollection', 'features': data}),
              200,
              headers: {'x-nowave-marine-status': degraded ? mode : 'ok'},
            );
          } finally {
            active--;
          }
        }),
      );
      addTearDown(viewport.dispose);
      List<String> drawn(String source) =>
          (jsonDecode(map.style.data[source]!)['features'] as List)
              .map((f) => f['id'].toString())
              .toList();
      void oldPresent() {
        expect(drawn('nowave-underwater-hazards').toSet(), {
          'polygon-z12',
          'multi-polygon-z12',
          'line-z12',
          'multi-line-z12',
        });
        expect(drawn('nowave-soundings'), ['modeled-cell-z12']);
      }

      await viewport.synchronize(map);
      oldPresent();
      map.zoom = 13;
      final pending = viewport.synchronize(map);
      await until(() => viewport.requests > 45);
      oldPresent();
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      viewport.styleLoaded();
      map.style.data.clear();
      final reload = viewport.synchronize(map);
      await until(
        () =>
            map.style.data.containsKey('nowave-underwater-hazards') &&
            map.style.data.containsKey('nowave-soundings'),
      );
      oldPresent();
      gate13.complete();
      await Future.wait([pending, reload]);
      oldPresent();
      mode = 'degraded';
      clock = clock.add(const Duration(seconds: 16));
      await viewport.synchronize(map);
      oldPresent();
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      mode = 'partial';
      clock = clock.add(const Duration(seconds: 16));
      await viewport.synchronize(map);
      oldPresent();
      mode = 'ok';
      clock = clock.add(const Duration(seconds: 16));
      await viewport.synchronize(map);
      expect(drawn('nowave-underwater-hazards').toSet(), {
        'polygon-z13',
        'multi-polygon-z13',
        'line-z13',
        'multi-line-z13',
      });
      expect(drawn('nowave-soundings'), ['modeled-cell-z13']);
      map.zoom = 14;
      final pending14 = viewport.synchronize(map);
      await until(() => viewport.requests > 90);
      expect(drawn('nowave-underwater-hazards').toSet(), {
        'polygon-z13',
        'multi-polygon-z13',
        'line-z13',
        'multi-line-z13',
      });
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      gate14.complete();
      await pending14;
      expect(drawn('nowave-underwater-hazards').toSet(), {
        'polygon-z14',
        'multi-polygon-z14',
        'line-z14',
        'multi-line-z14',
      });
      expect(drawn('nowave-soundings'), ['modeled-cell-z14']);
      expect(peak, lessThanOrEqualTo(2));
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      expect(
        viewport.metrics['cache_encoded_bytes'] as int,
        lessThanOrEqualTo(12 * 1024 * 1024),
      );
      map.longitude = 30;
      await viewport.synchronize(map);
      expect(drawn('nowave-underwater-hazards'), isEmpty);
      expect(drawn('nowave-soundings'), isEmpty);
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
    },
  );

  test(
    'saturated cache keeps displayed polygon within the 12 MiB cap',
    () async {
      final map = ViewMap()..zoom = 12;
      final body = jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'large-polygon',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [5.92, 43.07],
                  [5.94, 43.07],
                  [5.94, 43.09],
                  [5.92, 43.07],
                ],
              ],
            },
            'properties': {'payload': 'a' * (2 * 1024 * 1024)},
          },
        ],
      });
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://marine.example',
        clientFactory: () => MockClient(
          (request) async => http.Response(
            request.url.path.contains('underwater-hazards')
                ? body
                : '{"type":"FeatureCollection","features":[]}',
            200,
          ),
        ),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      expect(
        viewport.features('underwater-hazards').single['id'],
        'large-polygon',
      );
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      expect(
        viewport.metrics['cache_encoded_bytes'] as int,
        lessThanOrEqualTo(12 * 1024 * 1024),
      );
      map.zoom = 13;
      await viewport.synchronize(map);
      expect(
        viewport.features('underwater-hazards').single['id'],
        'large-polygon',
      );
      expect(viewport.metrics['cache_entries'] as int, lessThanOrEqualTo(64));
      expect(
        viewport.metrics['cache_encoded_bytes'] as int,
        lessThanOrEqualTo(12 * 1024 * 1024),
      );
      expect(viewport.errors, greaterThan(0));
    },
  );

  test(
    'continuous camera movement loads and renders during five seconds',
    () async {
      final map = ViewMap()..zoom = 9;
      var active = 0, peak = 0;
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://marine.example',
        clientFactory: () => MockClient((_) async {
          active++;
          peak = peak < active ? active : peak;
          await Future<void>.delayed(const Duration(milliseconds: 45));
          active--;
          return http.Response(
            jsonEncode({
              'type': 'FeatureCollection',
              'features': [harbour('moving-port')],
            }),
            200,
          );
        }),
      );
      addTearDown(viewport.dispose);
      final end = DateTime.now().add(const Duration(seconds: 5));
      var sawRenderedWhileMoving = false;
      while (DateTime.now().isBefore(end)) {
        if (DateTime.now().isAfter(
          end.subtract(const Duration(milliseconds: 2500)),
        )) {
          map.longitude = 10;
        }
        map.bearing += 2;
        viewport.schedule(map, cameraChanged: true);
        if (DateTime.now().isBefore(end.subtract(const Duration(seconds: 1))) &&
            map.style.data['nowave-harbours']?.contains('moving-port') ==
                true) {
          sawRenderedWhileMoving = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      await until(() => (viewport.metrics['active'] as int) == 0);
      expect(sawRenderedWhileMoving, isTrue);
      expect(viewport.requests, 18);
      expect(viewport.metrics['cache_entries'], 9);
      expect(peak, lessThanOrEqualTo(2));
      expect(map.cameraReads, inInclusiveRange(1, 35));
      expect(viewport.cancelled, 0);
    },
  );

  test('useful late response survives rotation and stale response is discarded on pan', () async {
    final map = ViewMap()..zoom = 9;
    final pending = <Completer<http.Response>>[];
    var active = 0, peak = 0;
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://marine.example',
      clientFactory: () => MockClient((request) async {
        active++;
        peak = peak < active ? active : peak;
        final response = pending.length < 2
            ? (() {
                final completer = Completer<http.Response>();
                pending.add(completer);
                return completer.future;
              })()
            : Future.value(
                http.Response(
                  jsonEncode({
                    'type': 'FeatureCollection',
                    'features': [
                      harbour(map.longitude < 20 ? 'useful' : 'new'),
                    ],
                  }),
                  200,
                ),
              );
        final result = await response;
        active--;
        return result;
      }),
    );
    addTearDown(viewport.dispose);
    final first = viewport.synchronize(map);
    await until(() => viewport.requests >= 2);
    map.bearing = 90;
    final rotated = viewport.synchronize(map);
    expect(viewport.cancelled, 0);
    for (final completer in pending) {
      completer.complete(
        http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [harbour('useful')],
          }),
          200,
        ),
      );
    }
    await Future.wait([first, rotated]);
    expect(
      viewport.features('harbours').map((f) => f['id']),
      contains('useful'),
    );
    expect(peak, lessThanOrEqualTo(2));

    // A new slow request becomes useless after a significant geographic pan.
    map.longitude = 30;
    final moved = viewport.synchronize(map);
    await moved;
    expect(
      viewport.features('harbours').map((f) => f['id']),
      isNot(contains('useful')),
    );
    expect(viewport.features('harbours').map((f) => f['id']), contains('new'));
  });

  test(
    'pan cancels obsolete flights and rejects their late responses',
    () async {
      final map = ViewMap()..zoom = 9;
      final old = <Completer<http.Response>>[];
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://marine.example',
        clientFactory: () => MockClient((_) async {
          if (old.length < 2) {
            final completer = Completer<http.Response>();
            old.add(completer);
            return completer.future;
          }
          return http.Response(
            jsonEncode({
              'type': 'FeatureCollection',
              'features': [harbour('new-area')],
            }),
            200,
          );
        }),
      );
      addTearDown(viewport.dispose);
      final first = viewport.synchronize(map);
      await until(() => old.length == 2);
      map.longitude = 30;
      final second = viewport.synchronize(map);
      await until(() => viewport.cancelled == 2);
      for (final response in old) {
        response.complete(
          http.Response(
            jsonEncode({
              'type': 'FeatureCollection',
              'features': [harbour('obsolete')],
            }),
            200,
          ),
        );
      }
      await Future.wait([first, second]);
      expect(
        viewport.features('harbours').map((f) => f['id']),
        isNot(contains('obsolete')),
      );
      expect(
        viewport.features('harbours').map((f) => f['id']),
        contains('new-area'),
      );
      expect(viewport.metrics['cache_entries'], 9);
    },
  );

  test('pause, resume, style reload and dispose reject late data', () async {
    final map = ViewMap()..zoom = 9;
    final pending = Completer<http.Response>();
    var firstCall = true;
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://marine.example',
      clientFactory: () => MockClient((_) async {
        if (firstCall) {
          firstCall = false;
          return pending.future;
        }
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [harbour('resumed')],
          }),
          200,
        );
      }),
    );
    final loading = viewport.synchronize(map);
    await until(() => viewport.requests >= 2);
    viewport.pause();
    expect(viewport.cancelled, 1);
    pending.complete(
      http.Response(
        jsonEncode({
          'type': 'FeatureCollection',
          'features': [harbour('late-paused')],
        }),
        200,
      ),
    );
    await loading;
    expect(
      viewport.features('harbours').map((f) => f['id']),
      isNot(contains('late-paused')),
    );
    final beforeResume = viewport.requests;
    viewport.resume(map);
    await until(
      () =>
          viewport.requests > beforeResume &&
          (viewport.metrics['cache_entries'] as int) == 9,
    );
    expect(
      viewport.features('harbours').map((f) => f['id']),
      contains('resumed'),
    );
    viewport.styleLoaded();
    map.style.data.clear();
    await viewport.synchronize(map);
    expect(map.style.data['nowave-harbours'], contains('resumed'));
    viewport.dispose();
    final requests = viewport.requests;
    await viewport.synchronize(map);
    expect(viewport.requests, requests);
    expect(viewport.metrics['active'], 0);
  });

  test('503 and timeout retry after backoff without caching a false empty snapshot', () async {
    final map = ViewMap();
    var clock = DateTime.utc(2026, 10, 22);
    var attempts = 0;
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://marine.example',
      now: () => clock,
      clientFactory: () => MockClient((_) async {
        attempts++;
        if (attempts <= 9) return http.Response('{}', 503);
        if (attempts <= 18) throw TimeoutException('network timeout');
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [harbour('recovered')],
          }),
          200,
        );
      }),
    );
    addTearDown(viewport.dispose);
    await viewport.synchronize(map);
    expect(viewport.metrics['cache_entries'], 0);
    expect(viewport.errors, 9);
    clock = clock.add(const Duration(seconds: 16));
    await viewport.synchronize(map);
    expect(viewport.metrics['cache_entries'], 0);
    expect(viewport.errors, 18);
    clock = clock.add(const Duration(seconds: 16));
    await viewport.synchronize(map);
    expect(viewport.metrics['cache_entries'], 9);
    expect(
      viewport.features('harbours').map((f) => f['id']),
      contains('recovered'),
    );
  });
}
