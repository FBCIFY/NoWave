import 'package:blueway/features/map/presentation/widgets/map_scale_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('la règle mesure la vraie distance, à toutes les latitudes', () {
    for (final latitude in [0.0, 43.3, 60.0, -48.4]) {
      for (final zoom in [5.0, 8.5, 12.0, 16.0, 20.0]) {
        for (final nautical in [true, false]) {
          final scale = MapScaleBar.measure(
            zoom: zoom,
            latitude: latitude,
            nautical: nautical,
          )!;
          final perPixel = MapScaleBar.metersPerPixel(
            zoom: zoom,
            latitude: latitude,
          );
          expect(scale.width, lessThanOrEqualTo(MapScaleBar.maxWidth));
          // Une valeur ronde sur 1, 2, 5 : la suivante dépasserait.
          expect(scale.width, greaterThan(MapScaleBar.maxWidth / 2.6));
          expect(scale.width * perPixel, greaterThan(0));
        }
      }
    }
  });

  test('valeurs rondes en milles nautiques, en mètres sous 0,1 NM', () {
    // Équateur, zoom 10 : 76,4 m par pixel, 80 px = 6,1 km = 3,3 NM.
    final nm = MapScaleBar.measure(zoom: 10, latitude: 0, nautical: true)!;
    expect(nm.label, '2 NM');
    expect(nm.width, closeTo(2 * 1852 / 76.437, 0.05));

    final km = MapScaleBar.measure(zoom: 10, latitude: 0, nautical: false)!;
    expect(km.label, '5 km');

    // Zoom 12 : 80 px = 0,83 NM ; zoom 16 : 80 px = 95 m.
    final half = MapScaleBar.measure(zoom: 12, latitude: 0, nautical: true)!;
    expect(half.label, '0,5 NM');

    final short = MapScaleBar.measure(zoom: 16, latitude: 0, nautical: true)!;
    expect(short.label, '50 m');
  });

  test('pas d’échelle sur le globe lointain', () {
    expect(
      MapScaleBar.measure(zoom: 4.9, latitude: 45, nautical: true),
      isNull,
    );
  });

  testWidgets('un appui bascule NM ↔ km et le choix est gardé', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final camera = ValueNotifier<MapScaleCamera>((zoom: 10, latitude: 0));
    addTearDown(camera.dispose);
    Future<void> pumpBar() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapScaleBar(key: UniqueKey(), camera: camera),
        ),
      ),
    );

    await pumpBar();
    await tester.pump();
    expect(find.text('2 NM'), findsOneWidget);

    await tester.tap(find.byType(MapScaleBar));
    await tester.pump();
    expect(find.text('5 km'), findsOneWidget);

    // Relancement : un nouveau widget relit le choix.
    await pumpBar();
    await tester.pump();
    expect(find.text('5 km'), findsOneWidget);

    camera.value = (zoom: 4, latitude: 0);
    await tester.pump();
    expect(find.text('5 km'), findsNothing);
  });
}
