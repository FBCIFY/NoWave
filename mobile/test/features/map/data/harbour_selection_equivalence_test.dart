import 'dart:math' as math;

import 'package:blueway/features/map/data/marine_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../support/harbour_selection_reference.dart';
import 'marine_viewport_test.dart' show harbour;

void main() {
  for (final count in [10, 100, 1000]) {
    test(
      'grid equals reference across rotation, pitch and visibility: $count ports',
      () {
        final random = math.Random(220 + count);
        final features = [
          for (var i = 0; i < count; i++)
            {
              ...harbour('port-$i'),
              'properties': {
                'name': i % 3 == 0 ? '' : 'Port $i',
                'category': i % 5 == 0 ? 'marina' : 'harbour',
              },
            },
        ];
        final xy = [
          for (var i = 0; i < count; i++)
            (
              random.nextDouble() * 2400 - 200,
              random.nextDouble() * 2400 - 200,
            ),
        ];
        final actual = HarbourSelection();
        final reference = ReferenceHarbourSelection();
        for (var step = 0; step < 30; step++) {
          final angle = step * math.pi / 9;
          final pixels = [
            for (var i = 0; i < count; i++)
              i % 17 == step % 17
                  ? null
                  : ScreenCoordinate(
                      x:
                          xy[i].$1 * math.cos(angle) -
                          xy[i].$2 * math.sin(angle),
                      y:
                          (xy[i].$1 * math.sin(angle) +
                              xy[i].$2 * math.cos(angle)) *
                          (step.isEven ? 1 : .5),
                    ),
          ];
          final zoom = [7.99, 8.0, 9.99, 10.0, 12.0, 13.0, 18.0][step % 7];
          expect(
            actual.select(features, pixels, zoom, 2000, 2000),
            reference.select(features, pixels, zoom, 2000, 2000),
            reason: 'step $step',
          );
          expect(actual.order, reference.order);
        }
      },
    );
  }

  test(
    'exact spacing, neighbouring buckets, negative positions and stacked ports',
    () {
      const s = 24 * 1.12 + 6;
      final features = [for (var i = 0; i < 16; i++) harbour('$i')];
      final actual = HarbourSelection(),
          reference = ReferenceHarbourSelection();
      final pixels = [
        for (final (x, y) in [
          (-s, -s),
          (0.0, 0.0),
          (s, 0.0),
          (s - 1e-10, 0.0),
          (s + 1e-10, s),
          (-s + 1e-10, s),
          (-1e-10, s),
          (2 * s, 2 * s),
          (s, s),
          (0.0, 0.0),
          (2000 + s, 0.0),
          (2000 + s + 1e-10, 0.0),
          (0.0, -s - 1e-10),
          (double.nan, 0.0),
          (double.infinity, 0.0),
          (0.0, double.negativeInfinity),
        ])
          ScreenCoordinate(x: x, y: y),
      ];
      for (var step = 0; step < 4; step++) {
        expect(
          actual.select(features, pixels, 13, 2000, 2000),
          reference.select(features, pixels, 13, 2000, 2000),
        );
        pixels[step] = ScreenCoordinate(x: -100, y: -100);
      }
    },
  );
}
