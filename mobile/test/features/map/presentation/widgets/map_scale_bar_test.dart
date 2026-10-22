import 'package:blueway/features/map/presentation/widgets/map_scale_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la règle mesure la vraie distance, à toutes les latitudes', () {
    for (final latitude in [0.0, 43.3, 60.0, -48.4]) {
      for (final zoom in [5.0, 8.5, 12.0, 16.0, 20.0]) {
        final scale = MapScaleBar.measure(zoom: zoom, latitude: latitude)!;
        expect(scale.width, lessThanOrEqualTo(MapScaleBar.maxWidth));
        // Une valeur ronde sur 1, 2, 5 : la suivante dépasserait.
        expect(scale.width, greaterThan(MapScaleBar.maxWidth / 2.6));
      }
    }
  });

  test('milles nautiques, puis pieds sous 0,1 NM, jamais de km', () {
    // Équateur, zoom 10 : 76,4 m par pixel, 80 px = 6,1 km = 3,3 NM.
    final nm = MapScaleBar.measure(zoom: 10, latitude: 0)!;
    expect(nm.label, '2 NM');
    expect(nm.width, closeTo(2 * 1852 / 76.437, 0.05));

    // Zoom 12 : 80 px = 0,83 NM ; zoom 15 : 191 m, 0,1 NM tient encore.
    expect(MapScaleBar.measure(zoom: 12, latitude: 0)!.label, '0,5 NM');
    expect(MapScaleBar.measure(zoom: 15, latitude: 0)!.label, '0,1 NM');

    // Zoom 16 : 80 px = 95 m = 313 ft ; zoom 20 : 6 m = 20 ft.
    expect(MapScaleBar.measure(zoom: 16, latitude: 0)!.label, '200 ft');
    expect(MapScaleBar.measure(zoom: 20, latitude: 0)!.label, '10 ft');

    for (var zoom = 5.0; zoom <= 22; zoom += 0.5) {
      final label = MapScaleBar.measure(zoom: zoom, latitude: 43.3)!.label;
      expect(label, anyOf(endsWith(' NM'), endsWith(' ft')));
    }
  });

  test('pas d’échelle sur le globe lointain', () {
    expect(MapScaleBar.measure(zoom: 4.9, latitude: 45), isNull);
  });

  testWidgets('la règle suit le zoom et disparaît sur le globe', (
    tester,
  ) async {
    final camera = ValueNotifier<MapScaleCamera>((zoom: 10, latitude: 0));
    addTearDown(camera.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MapScaleBar(camera: camera)),
      ),
    );
    expect(find.text('2 NM'), findsOneWidget);

    camera.value = (zoom: 16, latitude: 0);
    await tester.pump();
    expect(find.text('200 ft'), findsOneWidget);

    camera.value = (zoom: 4, latitude: 0);
    await tester.pump();
    expect(find.textContaining('ft'), findsNothing);
    expect(find.textContaining('NM'), findsNothing);
  });
}
