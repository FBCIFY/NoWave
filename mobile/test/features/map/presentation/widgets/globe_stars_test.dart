import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:blueway/features/map/presentation/widgets/globe_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> pixels(WidgetTester tester, GlobalKey key) async {
  late Uint8List result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      result = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
  return result;
}

void main() {
  test('les étoiles conservent les anciens seuils de fondu en zoom', () {
    expect(GlobeStars.intensityAt(0), .65);
    expect(GlobeStars.intensityAt(3), .4);
    expect(GlobeStars.intensityAt(6), 0);
    expect(GlobeStars.intensityAt(12), 0);
    expect(GlobeStars.intensityAt(.65), closeTo(.5958333333, 1e-9));
    expect(
      GlobeStars.intensityAt(3 - 1e-8),
      closeTo(GlobeStars.intensityAt(3 + 1e-8), 1e-8),
    );
  });

  testWidgets(
    'champ strictement stable après trois minutes et reconstruction',
    (tester) async {
      final zoom = ValueNotifier(.65);
      final key = GlobalKey();
      Widget scene() => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 600,
            child: RepaintBoundary(
              key: key,
              child: GlobeStars(zoom: zoom),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      final initial = await pixels(tester, key);
      await tester.pump(const Duration(seconds: 180));
      await tester.pumpWidget(scene());
      expect(await pixels(tester, key), orderedEquals(initial));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      zoom.dispose();
    },
  );

  testWidgets('le fondu retire les étoiles à Z6 et garde le fond spatial', (
    tester,
  ) async {
    final zoom = ValueNotifier(.65);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: GlobeStars(zoom: zoom),
        ),
      ),
    );
    final visible = await pixels(tester, key);
    zoom.value = 6;
    await tester.pump();
    final hidden = await pixels(tester, key);
    expect(visible, isNot(orderedEquals(hidden)));
    for (var index = 0; index < hidden.length; index += 4) {
      if (hidden[index] != 1 ||
          hidden[index + 1] != 3 ||
          hidden[index + 2] != 11 ||
          hidden[index + 3] != 255) {
        fail(
          'Une étoile ou une transparence subsiste à Z6, pixel ${index ~/ 4}',
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    zoom.dispose();
  });
}
