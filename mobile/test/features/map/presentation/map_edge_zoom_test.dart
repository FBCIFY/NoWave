import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/presentation/widgets/map_edge_zoom.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../support/focus_fakes.dart';

CameraChangedEventData _camera(double zoom) => CameraChangedEventData.fromJson({
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
});

Future<FocusMap> _openMap(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: MapScreen()));
  final map = FocusMap();
  final widget = tester.widget<MapWidget>(find.byType(MapWidget));
  widget.onMapCreated!(map);
  await tester.pump();
  widget.onCameraChangeListener!(_camera(10));
  await tester.pump();
  map.cameras.clear();
  return map;
}

/// Glisse verticalement de [dy] sur [finder], en petits pas.
Future<void> _slide(
  WidgetTester tester,
  Finder finder,
  double dy, {
  bool fromTop = false,
}) async {
  final rect = tester.getRect(finder);
  final start = fromTop ? Offset(rect.center.dx, rect.top + 64) : rect.center;
  final gesture = await tester.startGesture(start);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(0, dy / 10));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final side in ['left', 'right']) {
    testWidgets(
      'bord $side : glisser vers le bas dézoome, vers le haut zoome, 70 % plus vite',
      (tester) async {
        final map = await _openMap(tester);
        final edge = find.byKey(ValueKey('edge-zoom-$side'));

        // La portion occupée par le menu de droite sert à ses commandes.
        await _slide(tester, edge, 150, fromTop: true);
        // Le seuil de glissé de Flutter mange les premiers pixels.
        expect(map.cameras.last.zoom!.toDouble(), closeTo(8.3, .2));
        expect(
          map.cameras.map((camera) => camera.center),
          everyElement(isNull),
        );

        map.cameras.clear();
        await _slide(tester, edge, -150, fromTop: true);
        expect(map.cameras.last.zoom!.toDouble(), closeTo(11.7, .2));
      },
    );
  }

  testWidgets('au milieu de l’écran, le glissé reste à Mapbox', (tester) async {
    final map = await _openMap(tester);
    await _slide(tester, find.byType(MapWidget), MapEdgeZoom.pixelsPerZoom);
    expect(map.cameras.where((camera) => camera.zoom != null), isEmpty);
  });
}
