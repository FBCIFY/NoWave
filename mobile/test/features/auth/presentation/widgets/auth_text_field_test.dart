import 'package:blueway/features/auth/presentation/widgets/auth_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le champ garde sa hauteur en prenant le focus', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthTextField(
            controller: controller,
            label: 'E-mail',
            icon: Icons.email_outlined,
          ),
        ),
      ),
    );

    final before = tester.getSize(find.byType(TextField)).height;
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();

    // Le bouton « masquer le clavier » apparaît au bout du champ.
    expect(find.byTooltip('Masquer le clavier'), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).height, before);
    expect(before, lessThan(48));
  });
}
