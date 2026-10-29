import 'package:blueway/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('utilise Raleway avec des chiffres alignés, boutons compris', () {
    const liningFigures = FontFeature.liningFigures();
    final buttonStyle = appTheme.filledButtonTheme.style!.textStyle!.resolve(
      {},
    )!;

    for (final style in [
      appTheme.textTheme.bodyMedium!,
      appTheme.textTheme.titleLarge!,
      appTheme.textTheme.labelLarge!,
      buttonStyle,
    ]) {
      expect(style.fontFamily, 'Raleway');
      expect(style.fontFeatures, contains(liningFigures));
    }
  });

  testWidgets('un appui long sur un bouton n’affiche pas de bulle', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: IconButton(
            tooltip: 'Recentrer sur ma position',
            onPressed: () {},
            icon: const Icon(Icons.my_location),
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(IconButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Recentrer sur ma position'), findsNothing);
    // Toujours lu par VoiceOver et TalkBack.
    expect(
      tester.getSemantics(find.byType(IconButton)),
      matchesSemantics(
        tooltip: 'Recentrer sur ma position',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });
}
