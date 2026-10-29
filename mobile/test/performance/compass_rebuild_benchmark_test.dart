import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../features/map/support/focus_fakes.dart';

class _Headings extends DeviceOrientationService {
  final values = StreamController<double>.broadcast(sync: true);
  @override
  Stream<double> get mapHeadings => values.stream;
}

void main() {
  testWidgets(
    'NW-201 mesure les reconstructions dues au cap, sans seuil de performance natif',
    (tester) async {
      final gps = FocusGps()..initial.complete(focusPosition());
      final headings = _Headings();
      final map = FocusMap();
      final previous = debugOnRebuildDirtyWidget;
      var mapBuilds = 0;
      var nativeWidgetBuilds = 0;
      var glyphBuilds = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MapScreen(locationService: gps, orientationService: headings),
          ),
        );
        tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onMapCreated!(
          map,
        );
        await tester.pumpAndSettle();
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previous?.call(element, builtOnce);
          if (element.widget is MapScreen) mapBuilds++;
          if (element.widget is mb.MapWidget) nativeWidgetBuilds++;
          if (element.widget.runtimeType.toString() == '_NavigationGlyph') {
            glyphBuilds++;
          }
        };
        final costs = <int>[];
        for (var i = 0; i < 120; i++) {
          final clock = Stopwatch()..start();
          headings.values.add((i * 2 + 1).toDouble());
          await tester.pump(const Duration(milliseconds: 20));
          clock.stop();
          costs.add(clock.elapsedMicroseconds);
        }
        final rotatingBuilds = mapBuilds;
        final rotatingNativeBuilds = nativeWidgetBuilds;
        await tester.pumpAndSettle();
        mapBuilds = 0;
        nativeWidgetBuilds = 0;
        for (var i = 0; i < 120; i++) {
          headings.values.add(239);
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(rotatingBuilds, 0);
        expect(rotatingNativeBuilds, 0);
        expect(glyphBuilds, greaterThan(0));
        expect(mapBuilds, 0);
        expect(nativeWidgetBuilds, 0);
        costs.sort();
        // Mesure locale debug avec Mapbox simulé : ne constitue pas une recette
        // des frames UI/raster sur téléphone ni un verdict d'optimisation.
        // ignore: avoid_print
        print(
          'COMPASS_BENCHMARK ${jsonEncode({'samples': costs.length, 'simulated_hz': 50, 'rotating_map_builds': rotatingBuilds, 'rotating_map_widget_builds': rotatingNativeBuilds, 'glyph_builds': glyphBuilds, 'stationary_map_builds': mapBuilds, 'pump_elapsed_median_us': costs[costs.length ~/ 2], 'pump_elapsed_p95_us': costs[(costs.length * 0.95).floor()]})}',
        );
      } finally {
        debugOnRebuildDirtyWidget = previous;
        await tester.pumpWidget(const SizedBox.shrink());
        await headings.values.close();
        await gps.close();
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}
