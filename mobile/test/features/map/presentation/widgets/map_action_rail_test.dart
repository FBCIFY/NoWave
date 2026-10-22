import 'package:blueway/features/map/presentation/widgets/map_action_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('barre fine en bas : manuel, position et photo seulement', (
    tester,
  ) async {
    final tapped = <int>[];
    await _mount(tester, tapped.add);
    final navigation = find.byTooltip('Action 1');
    final bounds = tester.getRect(navigation);
    expect(bounds.center.dx, 400);
    expect(bounds.center.dy, 560);
    expect(tester.getSize(find.byType(MapActionRail)).height, 56);
    expect(find.byType(IconButton).hitTestable(), findsNWidgets(3));
    expect(
      tester.getCenter(find.byTooltip('Action 0')).dx,
      lessThan(bounds.center.dx),
    );
    expect(
      tester.getCenter(find.byTooltip('Action 2')).dx,
      greaterThan(bounds.center.dx),
    );
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byTooltip('Action $index'));
      await tester.pumpAndSettle();
    }
    expect(tapped, [0, 1, 2]);
  });

  testWidgets(
    'glisser horizontalement donne accès aux autres commandes sans action',
    (tester) async {
      final tapped = <int>[];
      await _mount(tester, tapped.add);
      final rail = find.byType(MapActionRail);
      final start = tester.getCenter(find.byTooltip('Action 1'));
      final gesture = await tester.startGesture(tester.getCenter(rail));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(
        tester.getCenter(find.byTooltip('Action 1')).dx,
        lessThan(start.dx),
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      final beforeLoop = tester.getCenter(find.byTooltip('Action 1'));
      for (var index = 0; index < 5; index++) {
        final semantics = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Commandes de la carte',
          ),
        );
        semantics.properties.onIncrease!();
        await tester.pumpAndSettle();
      }
      expect(tapped, isEmpty);
      expect(tester.getCenter(find.byTooltip('Action 1')), beforeLoop);
    },
  );

  testWidgets('deux commandes : elles restent visibles et tactiles', (
    tester,
  ) async {
    final tapped = <int>[];
    await _mount(tester, tapped.add, count: 2);
    await tester.tap(find.byTooltip('Action 1'));
    await tester.pumpAndSettle();
    expect(tapped, [1]);
  });

  testWidgets('commande indisponible et gestes avec animations réduites', (
    tester,
  ) async {
    final tapped = <int>[];
    await _mount(tester, tapped.add, reduceMotion: true, disabled: 1);
    await tester.tap(find.byTooltip('Action 1'));
    await tester.drag(find.byType(MapActionRail), const Offset(-64, 0));
    await tester.pumpAndSettle();
    expect(tapped, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  ValueChanged<int> onTap, {
  int count = 5,
  int? disabled,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
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
                bottom: 12,
                child: Center(
                  child: MapActionRail(
                    initialActionId: '1',
                    actions: [
                      for (var index = 0; index < count; index++)
                        MapRailAction(
                          id: '$index',
                          label: 'Action $index',
                          icon: const Icon(Icons.circle_outlined),
                          onPressed: disabled == index
                              ? null
                              : () => onTap(index),
                        ),
                    ],
                  ),
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
