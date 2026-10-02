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
}
