import 'package:blueway/app/app.dart';
import 'package:blueway/features/home/presentation/home_screen.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('L’accueil ouvre la carte et affiche ses commandes', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp(home: HomeScreen()));

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byTooltip('Créer un signalement'), findsOneWidget);
    expect(find.byTooltip('Recentrer sur ma position'), findsOneWidget);
    expect(find.byTooltip('Aligner la carte sur le cap actuel'), findsNothing);
  });
}
