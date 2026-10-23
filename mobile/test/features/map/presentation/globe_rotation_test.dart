import 'dart:async';

import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/presentation/widgets/map_heading_tape.dart';
import 'package:flutter/material.dart' hide Size;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../support/focus_fakes.dart';

CameraState _camera({
  double zoom = .65,
  double longitude = -4.49,
  double latitude = 48.38,
  double pitch = 0,
}) => CameraState(
  center: Point(coordinates: Position(longitude, latitude)),
  zoom: zoom,
  bearing: 0,
  pitch: pitch,
  padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
);

class _Map extends FocusMap {
  CameraState current = _camera();
  void Function(CameraState)? onChange;
  int sizeQueries = 0;
  final pitchMoves = <CameraOptions>[];
  @override
  Future<Size> getSize() async {
    sizeQueries++;
    return Size(width: width, height: height);
  }

  @override
  Future<CameraState> getCameraState() async => current;
  void emit(CameraState camera) {
    current = camera;
    onChange?.call(camera);
  }

  @override
  Future<void> setCamera(CameraOptions camera) async {
    if (camera.center == null) {
      pitchMoves.add(camera);
    } else {
      cameras.add(camera);
    }
    emit(
      _camera(
        zoom: current.zoom,
        longitude:
            camera.center?.coordinates.lng.toDouble() ??
            current.center.coordinates.lng.toDouble(),
        latitude:
            camera.center?.coordinates.lat.toDouble() ??
            current.center.coordinates.lat.toDouble(),
        pitch: camera.pitch ?? current.pitch,
      ),
    );
  }
}

void main() {
  late FocusGps gps;
  setUp(() => gps = FocusGps()..onCurrent = () async => focusPosition());
  tearDown(() => gps.close());

  Future<_Map> open(
    WidgetTester tester, {
    MapFocusController? focus,
    bool reduced = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: MapScreen(locationService: gps, focusController: focus),
        ),
      ),
    );
    final widget = tester.widget<MapWidget>(find.byType(MapWidget));
    final map = _Map();
    map.onChange = (camera) => widget.onCameraChangeListener!(
      CameraChangedEventData.fromJson({
        'timestamp': 0,
        'cameraState': {
          'center': camera.center.toJson(),
          'zoom': camera.zoom,
          'pitch': camera.pitch,
          'bearing': camera.bearing,
          'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
        },
      }),
    );
    widget.onMapCreated!(map);
    widget.onStyleLoadedListener!(
      StyleLoadedEventData.fromJson({
        'timeInterval': {'begin': 0, 'end': 1},
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    return map;
  }

  Future<void> zoomOut(
    WidgetTester tester,
    _Map map, {
    double zoom = 4.5,
  }) async {
    map.emit(_camera(zoom: 14));
    final center = tester.getCenter(find.byType(MapWidget));
    final first = await tester.startGesture(
      center - const Offset(100, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(100, 0),
      pointer: 2,
    );
    map.emit(_camera(zoom: 6));
    map.emit(_camera(zoom: zoom));
    await first.up();
    final count = map.cameras.length;
    await tester.pump(const Duration(seconds: 1));
    expect(
      map.cameras.length,
      count,
      reason: 'Le second doigt garde la priorité',
    );
    await second.up();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 40));
  }

  testWidgets(
    'démarrage : suivi GPS sans rotation, même sur le globe initial',
    (tester) async {
      final map = await open(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(map.cameras, isEmpty);
      expect(gps.positions.hasListener, true);
      expect(
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
        isA<FollowPuckViewportState>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dézoom à Z4.5 : rotation depuis le cadrage GPS après les deux doigts',
    (tester) async {
      final map = await open(tester);
      await zoomOut(tester, map);
      expect(map.cameras, isNotEmpty);
      expect(map.cameras.first.center!.coordinates.lng, closeTo(-4.49, .1));
      expect(map.cameras.first.center!.coordinates.lat, 48.38);
      final nativeLocationCalls = map.location.settings.length;
      final sizeQueries = map.sizeQueries;
      await tester.pump(const Duration(seconds: 1));
      expect(map.cameras.last.center!.coordinates.lng, greaterThan(-4.49));
      expect(map.location.settings.length, nativeLocationCalls);
      expect(map.sizeQueries, sizeQueries);
      expect(
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
        isA<IdleViewportState>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'toucher sans dézoom : pause puis reprise depuis la caméra déplacée',
    (tester) async {
      final map = await open(tester);
      await zoomOut(tester, map);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MapWidget)),
      );
      map.emit(_camera(zoom: 2, longitude: 40, latitude: 30));
      final count = map.cameras.length;
      await tester.pump(const Duration(seconds: 2));
      expect(map.cameras.length, count);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 40));
      expect(map.cameras.length, greaterThan(count));
      expect(map.cameras[count].center!.coordinates.lng, closeTo(40, .1));
      expect(map.cameras[count].center!.coordinates.lat, 30);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'toucher sur les coordonnées : pause puis reprise aussi sur l’interface',
    (tester) async {
      final map = await open(tester);
      await zoomOut(tester, map, zoom: .7);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(MapHeadingTape.positionKey)),
      );
      final count = map.cameras.length;
      await tester.pump(const Duration(seconds: 1));
      expect(map.cameras.length, count);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 40));
      expect(map.cameras.length, greaterThan(count));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'inertie et retour au-dessus de Z4.5 empêchent un départ prématuré',
    (tester) async {
      final map = await open(tester);
      map.emit(_camera(zoom: 14));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MapWidget)),
      );
      map.emit(_camera(zoom: 4.5));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      map.emit(_camera(zoom: 4.4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(map.cameras, isEmpty);
      map.emit(_camera(zoom: 4.6));
      await tester.pump(const Duration(seconds: 1));
      expect(map.cameras, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('GPS tardif ne reprend pas la main après un geste', (
    tester,
  ) async {
    final fix = Completer<geo.Position>();
    gps.onCurrent = () => fix.future;
    final map = await open(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MapWidget)),
    );
    map.emit(_camera(zoom: 2));
    await gesture.up();
    fix.complete(focusPosition());
    await tester.pump();
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      isNot(isA<FollowPuckViewportState>()),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bouton GPS : priorité au suivi puis aucune reprise spontanée', (
    tester,
  ) async {
    final map = await open(tester);
    await zoomOut(tester, map);
    await tester.tap(find.byTooltip('Recentrer sur ma position'));
    await tester.pump();
    final count = map.cameras.length;
    await tester.pump(const Duration(seconds: 2));
    expect(map.cameras.length, count);
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      isA<FollowPuckViewportState>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signalement prioritaire dès une demande de cadrage', (
    tester,
  ) async {
    final focus = MapFocusController();
    final map = await open(tester, focus: focus);
    await zoomOut(tester, map);
    focus.focus(focusReport());
    await tester.pump();
    final count = map.cameras.length;
    await tester.pump(const Duration(seconds: 2));
    expect(map.cameras.length, count);
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      isA<IdleViewportState>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
  });

  testWidgets('création d’un signalement : arrêt avant lecture de la caméra', (
    tester,
  ) async {
    final map = await open(tester);
    await zoomOut(tester, map);
    await tester.tap(find.byTooltip('Créer un signalement'));
    await tester.pump();
    final count = map.cameras.length;
    await tester.pump(const Duration(seconds: 1));
    expect(map.cameras.length, count);
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      isA<CameraViewportState>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inactivité : arrêt immédiat et reprise au premier plan sans saut',
    (tester) async {
      final map = await open(tester);
      await zoomOut(tester, map);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final count = map.cameras.length;
      await tester.pump(const Duration(seconds: 30));
      expect(map.cameras.length, count);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(map.cameras.length, greaterThan(count));
      expect(
        map.cameras.last.center!.coordinates.lng.toDouble() -
            map.cameras[count - 1].center!.coordinates.lng.toDouble(),
        lessThan(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('réduction des animations : dézoom et GPS sans rotation', (
    tester,
  ) async {
    final map = await open(tester, reduced: true);
    await zoomOut(tester, map);
    await tester.pump(const Duration(seconds: 1));
    expect(map.cameras, isEmpty);
    expect(gps.positions.hasListener, true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
