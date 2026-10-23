import 'dart:async';
import 'dart:ui' as ui;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'marine_viewport_test.dart' show ViewMap, until;

CameraState camera(
  double zoom, {
  double longitude = 5.93,
  double bearing = 0,
  double pitch = 0,
}) => CameraState(
  center: Point(coordinates: Position(longitude, 43.08)),
  padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
  zoom: zoom,
  bearing: bearing,
  pitch: pitch,
);

class SlowCamera extends ViewMap {
  final read = Completer<CameraState>();
  final bounds = <double>[];
  @override
  Future<CameraState> getCameraState() {
    cameraReads++;
    return read.future;
  }

  @override
  Future<CoordinateBounds> coordinateBoundsForCamera(CameraOptions options) {
    bounds.add(options.zoom!);
    return super.coordinateBoundsForCamera(options);
  }
}

class SlowBounds extends ViewMap {
  final read = Completer<CoordinateBounds>();
  var calls = 0;
  @override
  Future<CoordinateBounds> coordinateBoundsForCamera(CameraOptions options) {
    if (++calls == 1) return read.future;
    return super.coordinateBoundsForCamera(options);
  }
}

MarineViewport viewport(List<Uri> requests) => MarineViewport(
  viewportSize: () => const ui.Size(360, 805),
  apiBaseUrl: 'https://controlled.example',
  clientFactory: () => MockClient((request) async {
    requests.add(request.url);
    return http.Response('{"type":"FeatureCollection","features":[]}', 200);
  }),
);

void main() {
  test('stale bounds cannot start downloads for an obsolete camera', () async {
    final map = SlowBounds();
    final requests = <Uri>[];
    final view = viewport(requests);
    addTearDown(view.dispose);
    final old = view.synchronize(map, cameraState: camera(13));
    await view.synchronize(map, cameraState: camera(6));
    map.read.complete(
      await ViewMap().coordinateBoundsForCamera(CameraOptions()),
    );
    await old;
    await until(() => requests.length == 9 && view.metrics['active'] == 0);
    expect(requests.every((r) => r.path.contains('/harbours/6/')), isTrue);
  });

  test(
    'pausing during a bounds read prevents publication and downloads',
    () async {
      final map = SlowBounds();
      final requests = <Uri>[];
      final view = viewport(requests);
      addTearDown(view.dispose);
      final pending = view.synchronize(map, cameraState: camera(13));
      view.pause();
      map.read.complete(
        await ViewMap().coordinateBoundsForCamera(CameraOptions()),
      );
      await pending;
      expect(requests, isEmpty);
      expect(map.style.data, isEmpty);
    },
  );

  test(
    'event camera is reused, direct synchronization still reads native state',
    () async {
      final map = ViewMap();
      final requests = <Uri>[];
      final view = viewport(requests);
      addTearDown(view.dispose);
      await view.synchronize(map, cameraState: camera(13));
      expect(map.cameraReads, 0);
      expect(requests.length, 45);
      await view.synchronize(map);
      expect(map.cameraReads, 1);
    },
  );

  test('a late native read cannot replace a newer queued event', () async {
    final map = SlowCamera();
    final requests = <Uri>[];
    final view = viewport(requests);
    addTearDown(view.dispose);
    final first = view.synchronize(map);
    await Future<void>.delayed(Duration.zero);
    final latest = view.synchronize(map, cameraState: camera(13));
    map.read.complete(camera(6));
    await Future.wait([first, latest]);
    expect(map.bounds, isNotEmpty);
    expect(map.bounds.every((zoom) => zoom == 13), isTrue);
    expect(map.cameraReads, 1);
    expect(requests.where((r) => r.path.contains('/soundings/')), hasLength(9));
  });

  test('coalesced camera events keep the last zoom and do not read the native camera', () async {
    final map = ViewMap();
    final requests = <Uri>[];
    final view = viewport(requests);
    addTearDown(view.dispose);
    view.schedule(map, cameraState: camera(4));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    view.schedule(map, cameraState: camera(6));
    view.schedule(map, cameraState: camera(13));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(map.cameraReads, 0);
    expect(requests.where((r) => r.path.contains('/soundings/')), hasLength(9));
    expect(view.metrics['active'], 0);
  });

  test(
    'pause rejects an outstanding read and resume uses a fresh native camera',
    () async {
      final map = SlowCamera();
      final requests = <Uri>[];
      final view = viewport(requests);
      addTearDown(view.dispose);
      final pending = view.synchronize(map);
      view.pause();
      map.read.complete(camera(13));
      await pending;
      expect(requests, isEmpty);
      view.resume(ViewMap()..zoom = 6);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, hasLength(9));
    },
  );
}
