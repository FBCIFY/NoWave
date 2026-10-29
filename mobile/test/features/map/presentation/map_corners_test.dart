import 'package:blueway/features/map/presentation/map_corners.dart';
import 'package:blueway/features/map/presentation/widgets/map_action_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('l’axe calculé passe par le centre de la barre d’actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: MapActionRail(
            actions: [
              for (final id in ['a', 'b', 'c'])
                MapRailAction(
                  id: id,
                  label: id,
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
            ],
          ),
        ),
      ),
    );
    final rail = tester.getRect(find.byType(MapActionRail));
    expect(852 - rail.center.dy, MapCorners.railAxis(34));
    expect(rail.left, MapCorners.cornerWidth(393, 3));
  });

  test('iOS : « i » et logo centrés dans le coin gauche, sur l’axe', () {
    final corner = MapCorners.ornaments(
      screenWidth: 393,
      viewPaddingBottom: 34,
      actions: 3,
      ios: true,
    );
    final center = MapCorners.cornerWidth(393, 3) / 2;
    // Bouton de 44 pt, icône de 22 pt calée en bas ; Mapbox ajoute la zone
    // sûre lui-même.
    expect(corner.attribution.marginLeft! + 22, center);
    expect(corner.attribution.marginBottom! + 34 + 11, MapCorners.railAxis(34));
    // Le logo (85 pt) remplit presque le coin : la marge de 4 pt le décale
    // d’au plus un quart de point.
    expect(corner.logo.marginLeft! + 85 / 2, closeTo(center, 0.5));
    expect(corner.logo.marginBottom, corner.attribution.marginBottom! + 28);
  });

  test('Android : marges comptées depuis le bas de la carte', () {
    final corner = MapCorners.ornaments(
      screenWidth: 411,
      viewPaddingBottom: 24,
      actions: 2,
      ios: false,
    );
    final center = MapCorners.cornerWidth(411, 2) / 2;
    expect(corner.attribution.marginLeft! + 10.5, center);
    expect(corner.attribution.marginBottom! + 10.5, MapCorners.railAxis(24));
  });
}
