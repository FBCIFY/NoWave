import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../support/focus_fakes.dart';

CameraChangedEventData _camera({
  required double zoom,
  required double bearing,
}) => CameraChangedEventData.fromJson({
  'timestamp': 0,
  'cameraState': {
    'center': {
      'type': 'Point',
      'coordinates': [5.37, 43.29],
    },
    'zoom': zoom,
    'pitch': 0.0,
    'bearing': bearing,
    'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
  },
});

/// Rotation à deux doigts de [bearing] au zoom donné, puis lâcher.
Future<FocusMap> _rotateAndRelease(
  WidgetTester tester,
  double zoom, {
  double bearing = 40,
}) async {
  await tester.pumpWidget(const MaterialApp(home: MapScreen()));
  final map = FocusMap();
  final widget = tester.widget<MapWidget>(find.byType(MapWidget));
  widget.onMapCreated!(map);
  await tester.pump();
  widget.onCameraChangeListener!(_camera(zoom: zoom, bearing: 0));
  await tester.pump();

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(MapWidget)),
  );
  widget.onCameraChangeListener!(_camera(zoom: zoom, bearing: bearing));
  await tester.pump();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return map;
}

void main() {
  for (final zoom in [1.5, 3.0, 4.9]) {
    testWidgets('globe, zoom $zoom : la carte revient au nord au lâcher', (
      tester,
    ) async {
      final map = await _rotateAndRelease(tester, zoom);
      expect(map.easedCameras.map((camera) => camera.bearing), [0]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final zoom in [5.0, 10.0]) {
    testWidgets('dès les nuages, zoom $zoom : la rotation libre reste', (
      tester,
    ) async {
      final map = await _rotateAndRelease(tester, zoom);
      expect(map.easedCameras, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  /// Caps posés directement pendant le geste, sans animation.
  List<double?> limits(FocusMap map) => [
    for (final camera in map.cameras)
      if (camera.bearing != null && !map.easedCameras.contains(camera))
        camera.bearing?.toDouble(),
  ];

  testWidgets('globe : la rotation bute à 30° du nord pendant le geste', (
    tester,
  ) async {
    var map = await _rotateAndRelease(tester, 3.0);
    expect(limits(map), [30]);
    await tester.pumpWidget(const SizedBox.shrink());

    map = await _rotateAndRelease(tester, 3.0, bearing: 300);
    expect(limits(map), [-30]);
    await tester.pumpWidget(const SizedBox.shrink());

    map = await _rotateAndRelease(tester, 3.0, bearing: 20);
    expect(limits(map), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dès les nuages, la rotation n’a pas de butée', (tester) async {
    final map = await _rotateAndRelease(tester, 10.0, bearing: 120);
    expect(limits(map), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// Réglages des gestes envoyés à Mapbox, pour un seul champ.
  List<bool?> gestures(FocusMap map, bool? Function(GesturesSettings) field) =>
      [
        for (final settings in map.gestures.settings)
          if (field(settings) != null) field(settings),
      ];

  testWidgets('globe : deux doigts ne déplacent pas la carte', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));
    final map = FocusMap();
    final widget = tester.widget<MapWidget>(find.byType(MapWidget));
    widget.onMapCreated!(map);
    await tester.pump();
    // Réglages complets des mouvements à la création : hors sujet ici.
    map.gestures.settings.clear();
    for (final zoom in [3.0, 4.0, 6.0, 12.0, 2.0]) {
      widget.onCameraChangeListener!(_camera(zoom: zoom, bearing: 0));
      await tester.pump();
    }
    // Envoyé seulement au passage des nuages, pas à chaque image.
    expect(gestures(map, (settings) => settings.pinchPanEnabled), [
      false,
      true,
      false,
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('globe : les réglages des mouvements gardent le verrou', (
    tester,
  ) async {
    // Pont natif de l'inertie : absent des tests, il répondrait ainsi.
    const motion = MethodChannel('fr.blueway.app/map_motion');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(motion, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(motion, null));
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));
    final map = FocusMap();
    final widget = tester.widget<MapWidget>(find.byType(MapWidget));
    widget.onMapCreated!(map);
    await tester.pump();
    widget.onCameraChangeListener!(_camera(zoom: 3, bearing: 0));
    await tester.pump();
    map.gestures.settings.clear();

    // Réduire les animations renvoie tous les gestes à Mapbox.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(gestures(map, (settings) => settings.pinchPanEnabled), [
      true,
      false,
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('globe : à la butée, la rotation se coupe jusqu’au lâcher', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));
    final map = FocusMap();
    final widget = tester.widget<MapWidget>(find.byType(MapWidget));
    widget.onMapCreated!(map);
    await tester.pump();
    widget.onCameraChangeListener!(_camera(zoom: 3, bearing: 0));
    await tester.pump();
    map.gestures.settings.clear();
    bool? rotate(GesturesSettings settings) => settings.rotateEnabled;

    final first = await tester.startGesture(const Offset(150, 400));
    final second = await tester.startGesture(const Offset(250, 400));
    widget.onCameraChangeListener!(_camera(zoom: 3, bearing: 20));
    await tester.pump();
    expect(gestures(map, rotate), isEmpty);
    for (final bearing in [40.0, 45.0]) {
      widget.onCameraChangeListener!(_camera(zoom: 3, bearing: bearing));
      await tester.pump();
    }
    expect(gestures(map, rotate), [false]);

    // Un doigt encore posé : la rotation reste coupée.
    await first.up();
    await tester.pump();
    expect(gestures(map, rotate), [false]);
    await second.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(gestures(map, rotate), [false, true]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
