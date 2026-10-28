import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'marine_viewport_progressive_test.dart'
    show BoundsMap, pointIn, requestedCell, response;
import 'marine_viewport_test.dart' show until;

const mib = 1024 * 1024;

BoundsMap narrowMap(double zoom) => BoundsMap()
  ..zoom = zoom
  ..bounds = CoordinateBounds(
    southwest: Point(coordinates: Position(5.92999, 43.07999)),
    northeast: Point(coordinates: Position(5.93001, 43.08001)),
    infiniteBounds: false,
  );

Map<String, dynamic> densePort(MarineCell cell, int bytes) => {
  ...pointIn(cell, 'port-${cell.key}'),
  'properties': {'name': 'Port', 'category': 'harbour', 'payload': 'a' * bytes},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Z6 to Z14 releases offscreen parent coverage before margins finish', () async {
    final map = narrowMap(6);
    final gate = Completer<void>();
    var marginStarted = false;
    final viewport = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://controlled.example',
      clientFactory: () => MockClient((r) async {
        if (r.url.pathSegments[4] != 'harbours') return response([]);
        final cell = requestedCell(r);
        if (cell.z == 14 && !cell.contains(map.longitude, 43.08)) {
          marginStarted = true;
          await gate.future;
        }
        return response([densePort(cell, cell.z == 6 ? 3 * mib : 1100 * 1024)]);
      }),
    );
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      viewport.dispose();
    });
    await viewport.synchronize(map);
    final oldRequests = viewport.requests;
    final oldBytes = viewport.receivedBytes;
    map.zoom = 14;
    final loading = viewport.synchronize(map);
    await until(() => marginStarted);
    // Only the new centre and empty sibling families remain. The old Z6
    // parent has offscreen uncovered descendants, but no visible contribution.
    final pendingBytes = viewport.metrics['cache_encoded_bytes'] as int;
    expect(
      viewport.features('harbours').map((f) => f['id']),
      contains('port-${MarineCell.at(map.longitude, 43.08, 14).key}'),
    );
    gate.complete();
    await loading;

    final direct = MarineViewport(
      viewportSize: () => const ui.Size(360, 805),
      apiBaseUrl: 'https://controlled.example',
      clientFactory: () => MockClient(
        (r) async => r.url.pathSegments[4] == 'harbours'
            ? response([densePort(requestedCell(r), 1100 * 1024)])
            : response([]),
      ),
    );
    addTearDown(direct.dispose);
    await direct.synchronize(narrowMap(14));
    final warmIds = viewport.features('harbours').map((f) => f['id']).toSet();
    final coldIds = direct.features('harbours').map((f) => f['id']).toSet();
    // ignore: avoid_print
    print(
      'CACHE_COMPARISON ${jsonEncode({'warm_transition_requests': viewport.requests - oldRequests, 'warm_transition_bytes': viewport.receivedBytes - oldBytes, 'cold_requests': direct.requests, 'cold_bytes': direct.receivedBytes, 'warm_zooms': viewport.metrics['request_zooms'], 'cold_zooms': direct.metrics['request_zooms']})}',
    );
    expect(pendingBytes, lessThan(2 * mib));
    expect(warmIds, coldIds);
    expect(viewport.requests - oldRequests, direct.requests);
    expect(viewport.receivedBytes - oldBytes, direct.receivedBytes);
    expect((viewport.metrics['request_zooms'] as Map)['harbours'], 14);
    expect(viewport.metrics['budget_deferred'], 0);
    expect(
      viewport.metrics['cache_encoded_bytes'],
      lessThanOrEqualTo(12 * mib),
    );
  });

  test(
    'margin saturation preserves Z14 and does not retry after tiny savings',
    () async {
      final map = narrowMap(14);
      var now = DateTime.utc(2026, 10, 28);
      var refresh = false;
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://controlled.example',
        now: () => now,
        clientFactory: () => MockClient((r) async {
          if (r.url.pathSegments[4] != 'harbours') return response([]);
          return response([
            densePort(requestedCell(r), 2 * mib - (refresh ? 10 : 0)),
          ]);
        }),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      expect((viewport.metrics['request_zooms'] as Map)['harbours'], 14);
      expect(viewport.metrics['budget_refusals_visible'], 0);
      expect(viewport.metrics['budget_refusals_margin'], greaterThan(0));
      final requests = viewport.requests;
      now = now.add(const Duration(seconds: 20));
      await viewport.synchronize(map);
      expect(viewport.requests, requests);
      // Refresh frees only a few bytes: not enough for any deferred 2 MiB cell.
      refresh = true;
      now = now.add(const Duration(seconds: 301));
      final admitted = viewport.metrics['cache_entries'] as int;
      await viewport.synchronize(map);
      expect(viewport.requests - requests, admitted);
      expect((viewport.metrics['request_zooms'] as Map)['harbours'], 14);
      expect(viewport.errors, 0);
    },
  );

  test(
    'visible refresh evicts margins atomically and keeps central detail',
    () async {
      final map = narrowMap(14);
      var now = DateTime.utc(2026, 10, 28);
      var refresh = false;
      final viewport = MarineViewport(
        viewportSize: () => const ui.Size(360, 805),
        apiBaseUrl: 'https://controlled.example',
        now: () => now,
        clientFactory: () => MockClient((r) async {
          if (r.url.pathSegments[4] != 'harbours') return response([]);
          final cell = requestedCell(r);
          final central = cell.contains(map.longitude, 43.08);
          return response([
            densePort(cell, refresh && central ? 3 * mib : 1250 * 1024),
          ]);
        }),
      );
      addTearDown(viewport.dispose);
      await viewport.synchronize(map);
      refresh = true;
      now = now.add(const Duration(seconds: 301));
      await viewport.synchronize(map);
      expect(viewport.metrics['cache_margin_evictions'], greaterThan(0));
      expect(viewport.metrics['budget_refusals_visible'], 0);
      final centre = viewport
          .features('harbours')
          .singleWhere(
            (f) =>
                f['id'] ==
                'port-${MarineCell.at(map.longitude, 43.08, 14).key}',
          );
      // The stable point retains its published identity; the cache admitted the
      // refreshed larger cell without sacrificing its visible coverage.
      expect(centre['geometry']['type'], 'Point');
      expect((viewport.metrics['request_zooms'] as Map)['harbours'], 14);
      expect(
        viewport.metrics['cache_encoded_bytes'],
        lessThanOrEqualTo(12 * mib),
      );
      final count = viewport.requests;
      await viewport.synchronize(map);
      expect(viewport.requests, count);
    },
  );
}
