import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
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

/// Rotation à deux doigts de 40° au zoom donné, puis lâcher.
Future<FocusMap> _rotateAndRelease(WidgetTester tester, double zoom) async {
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
  widget.onCameraChangeListener!(_camera(zoom: zoom, bearing: 40));
  await tester.pump();
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return map;
}

void main() {
  testWidgets('zoom ≥ 7 : la carte revient au nord au lâcher des doigts', (
    tester,
  ) async {
    final map = await _rotateAndRelease(tester, 10);
    expect(map.easedCameras.map((camera) => camera.bearing), [0]);
    expect(
      find.byTooltip('Aligner la carte sur le cap actuel'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('globe : la rotation libre reste après le lâcher', (
    tester,
  ) async {
    final map = await _rotateAndRelease(tester, 5);
    expect(map.easedCameras, isEmpty);
    expect(find.byTooltip('Orienter la carte vers le nord'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
