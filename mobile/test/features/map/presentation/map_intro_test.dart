import 'dart:async';

import 'package:blueway/core/map/globe_style.dart';
import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/map/presentation/map_intro_controller.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
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

class _Headings extends DeviceOrientationService {
  final values = StreamController<double>.broadcast(sync: true);
  @override
  Stream<double> get mapHeadings => values.stream;
}

class _Map extends Fake implements MapboxMap {
  @override
  final location = _Location();
  @override
  final compass = _Compass();
  @override
  final scaleBar = _Scale();

  @override
  Future<void> cancelCameraAnimation() async {}

  @override
  Future<CameraBounds> getBounds() async => CameraBounds(
    bounds: CoordinateBounds(
      southwest: Point(coordinates: Position(-180, -85)),
      northeast: Point(coordinates: Position(180, 85)),
      infiniteBounds: true,
    ),
    minZoom: 0,
    maxZoom: 22,
    minPitch: 0,
    maxPitch: 85,
  );

  @override
  Future<CameraState> getCameraState() async => CameraState(
    center: Point(coordinates: Position(-4.49, 48.38)),
    zoom: 2,
    pitch: 40,
    bearing: 0,
    padding: MbxEdgeInsets(top: 0, left: 0, right: 0, bottom: 0),
  );
}

MapWidget _mapWidget(WidgetTester tester) =>
    tester.widget<MapWidget>(find.byType(MapWidget));

/// Carte sous l'onboarding, créée puis chargée.
Future<MapIntroController> _pumpCoveredMap(
  WidgetTester tester,
  FocusGps gps, {
  DeviceOrientationService? headings,
  _Map? map,
}) async {
  final intro = MapIntroController();
  addTearDown(intro.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MapScreen(
        locationService: gps,
        orientationService: headings,
        intro: intro,
      ),
    ),
  );
  _mapWidget(tester).onMapCreated!(map ?? _Map());
  await tester.pump();
  _mapWidget(tester).onMapLoadedListener!(
    MapLoadedEventData.fromJson({
      'timeInterval': {'begin': 0, 'end': 0},
    }),
  );
  return intro;
}

/// Les autres tests gardent un setCamera absent : Mapbox refuse le vol
/// d'arrivée, qui passe aussitôt la main au suivi GPS (FollowPuck).
class _HeadingMap extends _Map {
  final cameras = <CameraOptions>[];

  @override
  Future<void> setCamera(CameraOptions camera) async => cameras.add(camera);
}

void main() {
  late FocusGps gps;
  setUp(() => gps = FocusGps());
  tearDown(() => gps.close());

  testWidgets(
    'fin de l’onboarding : autorisation sous la photo, fondu, puis vol jusqu’à '
    'l’utilisateur',
    (tester) async {
      gps.onCurrent = () async => focusPosition();
      final intro = await _pumpCoveredMap(tester, gps);

      // Sous l'onboarding, rien ne demande la position.
      await tester.pump(const Duration(seconds: 1));
      expect(gps.permissionRequests, 0);
      expect(gps.currentRequests, 0);
      expect(_mapWidget(tester).viewport, isA<CameraViewportState>());

      intro.start();
      expect(intro.phase, MapIntroPhase.starting);
      await tester.pump();
      expect(gps.permissionRequests, 1);
      expect(intro.phase, MapIntroPhase.revealed);
      // Le vol attend la fin du fondu.
      expect(_mapWidget(tester).viewport, isA<CameraViewportState>());

      await tester.pump(MapIntroController.fadeDuration);
      await tester.pump();
      final viewport = _mapWidget(tester).viewport as FollowPuckViewportState;
      expect(viewport.zoom, 14);
      expect(gps.currentRequests, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'position refusée : pas de nouvelle fenêtre, la carte descend sur la France',
    (tester) async {
      gps.permissionError = StateError(
        'L’accès à votre position a été refusé.',
      );
      final intro = await _pumpCoveredMap(tester, gps);

      intro.start();
      await tester.pump();
      await tester.pump(MapIntroController.fadeDuration);
      await tester.pump();

      expect(gps.currentRequests, 0);
      final viewport = _mapWidget(tester).viewport as CameraViewportState;
      expect(viewport.zoom, 4.2);
      expect(viewport.center?.coordinates.lng, closeTo(2.4, 0.01));
      expect(viewport.center?.coordinates.lat, closeTo(46.6, 0.01));
      expect(
        find.text('L’accès à votre position a été refusé.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'GPS lent : la France en attendant, puis l’utilisateur dès sa position',
    (tester) async {
      final fix = Completer<geo.Position>();
      gps.onCurrent = () => fix.future;
      final intro = await _pumpCoveredMap(tester, gps);

      intro.start();
      await tester.pump();
      await tester.pump(MapIntroController.fadeDuration);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect((_mapWidget(tester).viewport as CameraViewportState).zoom, 4.2);

      fix.complete(focusPosition());
      await tester.pump();
      await tester.pump();
      expect(_mapWidget(tester).viewport, isA<FollowPuckViewportState>());

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cap mesuré sous l’onboarding : disponible dès le premier suivi de direction',
    (tester) async {
      gps.onCurrent = () async => focusPosition();
      final headings = _Headings();
      addTearDown(headings.values.close);
      final map = _HeadingMap();
      final intro = await _pumpCoveredMap(
        tester,
        gps,
        headings: headings,
        map: map,
      );
      // iOS n'envoie qu'une mesure tant que le téléphone ne tourne pas.
      headings.values.add(90);
      await tester.pump();
      expect(find.byIcon(Icons.navigation), findsNothing);

      intro.start();
      await tester.pump();
      await tester.pump(MapIntroController.fadeDuration);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Recentrer sur ma position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Suivre la direction du téléphone'));
      await tester.pumpAndSettle();
      final viewport = _mapWidget(tester).viewport as FollowPuckViewportState;
      // Le natif laisse le cap à la caméra de cap.
      expect(viewport.bearing, isNull);
      expect(map.cameras.last.bearing, 90);
      expect(find.byIcon(Icons.navigation), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('un doigt sur la carte pendant l’attente du GPS annule le vol', (
    tester,
  ) async {
    final fix = Completer<geo.Position>();
    gps.onCurrent = () => fix.future;
    final intro = await _pumpCoveredMap(tester, gps);

    intro.start();
    await tester.pump();
    await tester.pump(MapIntroController.fadeDuration);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MapWidget)),
    );
    await gesture.up();
    fix.complete(focusPosition());
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    // La carte reste où l'utilisateur l'a prise : le globe du lancement.
    final viewport = _mapWidget(tester).viewport as CameraViewportState;
    expect(viewport.zoom, GlobeStyle.initialZoom);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
