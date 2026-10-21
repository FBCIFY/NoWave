import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../support/focus_fakes.dart';

class _Location extends Fake implements LocationSettings {
  @override
  Future<void> updateSettings(LocationComponentSettings settings) async {}
}

class _Compass extends Fake implements CompassSettingsInterface {
  @override
  Future<void> updateSettings(CompassSettings settings) async {}
}

class _Scale extends Fake implements ScaleBarSettingsInterface {
  @override
  Future<void> updateSettings(ScaleBarSettings settings) async {}
}

class _Map extends Fake implements MapboxMap {
  @override
  final location = _Location();
  @override
  final compass = _Compass();
  @override
  final scaleBar = _Scale();
  final flights = <CameraOptions>[];
  final durations = <int?>[];

  @override
  Future<CameraState> getCameraState() async => CameraState(
    center: Point(coordinates: Position(-4.49, 48.38)),
    zoom: 2,
    pitch: 0,
    bearing: 0,
    padding: MbxEdgeInsets(top: 0, left: 0, right: 0, bottom: 0),
  );

  @override
  Future<void> flyTo(
    CameraOptions options,
    MapAnimationOptions? animation,
  ) async {
    flights.add(options);
    durations.add(animation?.duration);
  }
}

void main() {
  late FocusGps gps;
  setUp(() {
    gps = FocusGps()..onCurrent = () async => focusPosition();
  });
  tearDown(() => gps.close());

  testWidgets('GPS : suivi dès le lancement puis recentrage volontaire', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: MapScreen(locationService: gps)));
    final map = _Map();
    tester.widget<MapWidget>(find.byType(MapWidget)).onMapCreated!(map);
    await tester.pumpAndSettle();
    expect(map.flights, isEmpty);
    final initial =
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport
            as FollowPuckViewportState;
    expect(initial.zoom, 14);
    expect(initial.pitch, 60);
    expect(gps.positions.hasListener, true);
    expect(find.textContaining('Lat.'), findsOneWidget);
    gps.positions.add(focusPosition(latitude: 43.30));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      same(initial),
    );

    await tester.tap(find.byTooltip('Recentrer sur ma position'));
    await tester.pumpAndSettle();
    expect(map.flights, isEmpty);
    final viewport =
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport
            as FollowPuckViewportState;
    expect(viewport.zoom, 14);
    expect(viewport.pitch, 60);
    expect(viewport.bearing, isA<FollowPuckViewportStateBearingConstant>());

    gps.positions.add(focusPosition(latitude: 43.30));
    await tester.pumpAndSettle();
    expect(map.flights, isEmpty);
    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
      isA<FollowPuckViewportState>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'le badge Z suit les événements caméra sans remplacer les coordonnées',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MapScreen()));
      expect(find.text('Z 0.7'), findsOneWidget);
      final map = tester.widget<MapWidget>(find.byType(MapWidget));
      expect(map.mapOptions?.constrainMode, ConstrainMode.NONE);
      expect(map.isOpaque, false);
      expect(map.textureView, true);
      final viewport = map.viewport as CameraViewportState;
      expect(viewport.center?.coordinates.lng, 15);
      expect(viewport.center?.coordinates.lat, 12);
      for (final zoom in [2.0, 11.8, 15.5, 17.0]) {
        map.onCameraChangeListener!(
          CameraChangedEventData.fromJson({
            'timestamp': 0,
            'cameraState': {
              'center': {
                'type': 'Point',
                'coordinates': [5.37, 43.29],
              },
              'zoom': zoom,
              'pitch': 0.0,
              'bearing': 0.0,
              'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
            },
          }),
        );
        await tester.pump();
        expect(find.text('Z ${zoom.toStringAsFixed(1)}'), findsOneWidget);
        expect(find.text('Position indisponible'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
