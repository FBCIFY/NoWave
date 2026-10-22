import 'package:blueway/features/map/presentation/widgets/map_action_rail.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les actions secondaires se découvrent comme sur l'app : par un glissé.
Future<void> tapMapAction(WidgetTester tester, String label) async {
  final button = find.byTooltip(label).hitTestable();
  for (var attempt = 0; attempt < 5; attempt++) {
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      return;
    }
    await tester.timedDrag(
      find.byType(MapActionRail),
      const Offset(-64, 0),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
  }
  fail('Commande introuvable dans la barre : $label');
}
