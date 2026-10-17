import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/location/support/fake_geolocator.dart';

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
    pitch: 40,
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
  late geo.GeolocatorPlatform previous;
  late FakeGeolocator gps;
  setUp(() {
    previous = geo.GeolocatorPlatform.instance;
    geo.GeolocatorPlatform.instance = gps = FakeGeolocator();
  });
  tearDown(() => geo.GeolocatorPlatform.instance = previous);

  testWidgets(
    'GPS : vol du globe à Z 15.5, puis mises à jour sans suivi caméra',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MapScreen()));
      final map = _Map();
      tester.widget<MapWidget>(find.byType(MapWidget)).onMapCreated!(map);
      await tester.pumpAndSettle();
      // La collecte initiale du GPS ne déplace pas la caméra libre.
      expect(map.flights, isEmpty);
      expect(
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
        isNot(isA<FollowPuckViewportState>()),
      );

      await tester.tap(find.byTooltip('Recentrer sur ma position'));
      await tester.pumpAndSettle();
      expect(map.flights, hasLength(1));
      final flight = map.flights.single;
      expect(flight.center!.coordinates.lng, testPosition().longitude);
      expect(flight.center!.coordinates.lat, testPosition().latitude);
      expect(flight.zoom, 15.5);
      expect(flight.pitch, 0);
      expect(map.durations.single, 2200);
      expect(
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
        isA<IdleViewportState>(),
      );

      gps.emit(testPosition(latitude: 43.30));
      await tester.pumpAndSettle();
      expect(map.flights, hasLength(1));
      expect(
        tester.widget<MapWidget>(find.byType(MapWidget)).viewport,
        isA<IdleViewportState>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'le badge Z suit les événements caméra sans remplacer les coordonnées',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MapScreen()));
      expect(find.text('Z 7.0'), findsOneWidget);
      final map = tester.widget<MapWidget>(find.byType(MapWidget));
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
