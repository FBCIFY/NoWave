import 'dart:ui' as ui;

import 'package:blueway/core/map/cloud_passage_controller.dart';
import 'package:blueway/features/map/presentation/widgets/cloud_passage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> atlas() async {
    final data = await rootBundle.load('assets/globe/cloud-passage-atlas.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void camera(
    CloudPassageController controller,
    double zoom, {
    double lon = 6,
    double bearing = 0,
  }) => controller.setCamera(
    zoom: zoom,
    longitude: lon,
    latitude: 43,
    bearing: bearing,
    pitch: 0,
  );

  testWidgets(
    'real texture: holes, density variation, stable reverse, clear at Z6.2',
    (tester) async {
      await tester.runAsync(() async {
        final image = await atlas();
        final controller = CloudPassageController();
        final painter = CloudPassagePainter(camera: controller, atlas: image);
        try {
          Future<List<int>> pixels(
            double zoom, {
            double lon = 6,
            double bearing = 0,
          }) async {
            camera(controller, zoom, lon: lon, bearing: bearing);
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder), const Size(180, 360));
            final picture = recorder.endRecording();
            final frame = await picture.toImage(180, 360);
            picture.dispose();
            try {
              return (await frame.toByteData())!.buffer.asUint8List().toList();
            } finally {
              frame.dispose();
            }
          }

          final clear = await pixels(4);
          final entering = await pixels(4.7);
          final inside = await pixels(5.3);
          expect(clear.every((v) => v == 0), isTrue);
          final alphas = [for (var i = 3; i < inside.length; i += 4) inside[i]];
          expect(alphas.toSet().length, greaterThan(50));
          expect(
            alphas.where((v) => v < 20).length / alphas.length,
            greaterThan(.15),
          );
          expect(alphas.reduce((a, b) => a > b ? a : b), greaterThan(80));
          expect(entering, isNot(inside));
          expect(await pixels(6.2), clear);
          expect(await pixels(6.3), clear);
          expect(await pixels(7), clear);
          expect(await pixels(5.3), inside); // Same frame on reversing zoom.
          expect(await pixels(5.3, bearing: 360), inside);
          expect(await pixels(5.3, lon: -80), isNot(inside));
          expect(painter.hitTest(Offset.zero), isFalse);
        } finally {
          image.dispose();
          controller.dispose();
        }
      });
    },
  );

  testWidgets(
    'gestures pass through, controls stay usable, reduced motion removes foreground',
    (tester) async {
      final controller = CloudPassageController();
      camera(controller, 5.3);
      var mapTaps = 0;
      var buttonTaps = 0;
      Widget app({bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTaps++,
                child: const ColoredBox(color: Colors.blue),
              ),
              CloudPassage(camera: controller),
              Align(
                alignment: Alignment.bottomCenter,
                child: TextButton(
                  onPressed: () => buttonTaps++,
                  child: const Text('GPS'),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app());
      for (var i = 0; i < 40; i++) {
        if (tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .any((w) => w.painter is CloudPassagePainter)) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final clouds = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CloudPassagePainter,
      );
      expect(clouds, findsOneWidget);
      await tester.tapAt(const Offset(100, 100));
      await tester.tap(find.text('GPS'));
      expect(mapTaps, 1);
      expect(buttonTaps, 1);
      await tester.pumpWidget(app(reduced: true));
      expect(clouds, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
