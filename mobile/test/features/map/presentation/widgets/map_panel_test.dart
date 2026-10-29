import 'package:blueway/features/map/presentation/widgets/map_panel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final side in MapPanelSide.values) {
      testWidgets('$platform $side : suit le doigt puis revient en place', (
        tester,
      ) async {
        var closed = 0;
        await _mount(tester, platform, side, () => closed++);
        final surface = find.byKey(const ValueKey('map-panel-surface'));
        final start = tester.getTopLeft(surface);
        final direction = side == MapPanelSide.top ? -1.0 : 1.0;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('map-panel-drag-handle'))),
        );
        // Franchir le seuil de reconnaissance, puis mesurer le déplacement.
        await gesture.moveBy(Offset(0, direction * 20));
        await tester.pump();
        await gesture.moveBy(Offset(0, direction * 14));
        await tester.pump();
        expect(
          (tester.getTopLeft(surface).dy - start.dy) * direction,
          greaterThan(10),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(surface), start);
        expect(closed, 0);
      });

      testWidgets('$platform $side : ferme après un glissement suffisant', (
        tester,
      ) async {
        var closed = 0;
        await _mount(tester, platform, side, () => closed++);
        final direction = side == MapPanelSide.top ? -1.0 : 1.0;
        await tester.fling(
          find.byKey(const ValueKey('map-panel-drag-handle')),
          Offset(0, direction * 100),
          800,
        );
        await tester.pumpAndSettle();
        expect(closed, 1);
      });
    }

    testWidgets('$platform : présentation translucide et coins adaptés', (
      tester,
    ) async {
      await _mount(tester, platform, MapPanelSide.bottom, () {});
      final material = tester.widget<Material>(
        find.byKey(const ValueKey('map-panel-surface')),
      );
      expect(material.color!.a, lessThan(1));
      final radius = material.borderRadius!.resolve(TextDirection.ltr);
      expect(radius.topLeft, const Radius.circular(24));
      expect(
        radius.bottomLeft,
        platform == TargetPlatform.android
            ? Radius.zero
            : const Radius.circular(24),
      );
      expect(
        find.byType(CupertinoButton),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('animations réduites : fermeture immédiate et unique', (
    tester,
  ) async {
    var closed = 0;
    await _mount(
      tester,
      TargetPlatform.iOS,
      MapPanelSide.bottom,
      () => closed++,
      reduceMotion: true,
    );
    await tester.tap(find.byTooltip('Fermer'));
    expect(closed, 1);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });
}

Future<void> _mount(
  WidgetTester tester,
  TargetPlatform platform,
  MapPanelSide side,
  VoidCallback onClose, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            disableAnimations: reduceMotion,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: side == MapPanelSide.top ? 0 : null,
                bottom: side == MapPanelSide.bottom ? 0 : null,
                child: MapPanel(
                  side: side,
                  onClose: onClose,
                  child: const SizedBox(height: 180),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
