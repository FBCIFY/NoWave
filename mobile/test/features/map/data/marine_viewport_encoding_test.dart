import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'marine_viewport_test.dart' show ViewMap, ViewStyle, harbour, until;

class CountingStyle extends ViewStyle {
  int writes = 0;
  bool fail = false;
  Completer<void>? gate;
  int active = 0, maxActive = 0;
  @override
  Future<void> setStyleSourceProperty(
    String id,
    String key,
    Object value,
  ) async {
    writes++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (fail) {
        fail = false;
        throw StateError('temporary native publication failure');
      }
      await gate?.future;
      await super.setStyleSourceProperty(id, key, value);
    } finally {
      active--;
    }
  }
}

class EncodingMap extends ViewMap {
  @override
  final CountingStyle style = CountingStyle();
}

MarineViewport viewport(ViewMap map) => MarineViewport(
  viewportSize: () => const ui.Size(360, 805),
  apiBaseUrl: 'https://controlled.example',
  clientFactory: () => MockClient((request) async {
    final family = request.url.pathSegments[4];
    final feature = harbour(family);
    if (family == 'depth-contours') {
      feature['geometry'] = {
        'type': 'LineString',
        'coordinates': [
          [map.longitude, 43.08],
          [map.longitude + .01, 43.09],
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

void main() {
  test('warm data reuses exact encodings, style reload still republishes all five sources', () async {
    final map = EncodingMap()..zoom = 13;
    final view = viewport(map);
    addTearDown(view.dispose);
    await view.synchronize(map);
    final encodings = view.metrics['encodings'];
    final writes = map.style.writes;
    final data = Map.of(map.style.data);
    map.bearing = 90;
    for (var i = 0; i < 5; i++) {
      await view.synchronize(map);
    }
    expect(view.metrics['encodings'], encodings);
    expect(map.style.writes, writes);
    expect(map.style.data, data);
    view.styleLoaded();
    map.style.data.clear();
    await view.synchronize(map);
    expect(map.style.writes, writes + 5);
    expect(view.metrics['encodings'], encodings);
    expect(map.style.data, data);
    expect(view.requests, 45);
  });

  test(
    'a replacement geometry with the same ID must be encoded again',
    () async {
      final map = EncodingMap()..zoom = 13;
      final view = viewport(map);
      addTearDown(view.dispose);
      await view.synchronize(map);
      final source = MarineViewport.sources['depth-contours']!;
      final before = map.style.data[source];
      map.longitude = -70;
      await view.synchronize(map);
      final features = jsonDecode(map.style.data[source]!)['features'] as List;
      expect(features.single['id'], 'depth-contours');
      expect(features.single['geometry']['coordinates'][0][0], -70);
      expect(map.style.data[source], isNot(before));
    },
  );

  test(
    'failed native publication retries even with a cached encoding',
    () async {
      final map = EncodingMap()..zoom = 4;
      final view = viewport(map);
      addTearDown(view.dispose);
      map.style.fail = true;
      await view.synchronize(map);
      expect(map.style.data, isEmpty);
      await view.synchronize(map);
      expect(map.style.data.keys, containsAll(MarineViewport.sources.values));
    },
  );

  test(
    'style reload during an outstanding publication is serialized and repaired',
    () async {
      final map = EncodingMap()..zoom = 4;
      final view = viewport(map);
      addTearDown(view.dispose);
      final gate = map.style.gate = Completer<void>();
      final first = view.synchronize(map);
      await until(() => map.style.active == 1);
      view.styleLoaded();
      map.style.data.clear();
      await view.synchronize(map);
      map.style.gate = null;
      gate.complete();
      await first;
      await until(() => map.style.data.length == 5);
      expect(map.style.maxActive, 1);
      expect(map.style.writes, 6);
    },
  );
}
