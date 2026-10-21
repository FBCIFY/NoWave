import 'package:blueway/core/text/capitalize_first_letter_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _format(
  String text, {
  TextRange composing = TextRange.empty,
}) => const CapitalizeFirstLetterFormatter().formatEditUpdate(
  TextEditingValue.empty,
  TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
    composing: composing,
  ),
);

void main() {
  test('met la première lettre en majuscule et garde le reste', () {
    expect(_format('bouée à la dérive').text, 'Bouée à la dérive');
    expect(_format('éole').text, 'Éole');
    expect(_format('Marin').text, 'Marin');
  });

  test('ignore les espaces du début et garde le curseur', () {
    final value = _format('  belle île');
    expect(value.text, '  Belle île');
    expect(value.selection, const TextSelection.collapsed(offset: 11));
  });

  test('laisse les chiffres, le texte vide et les longueurs qui changent', () {
    expect(_format('').text, '');
    expect(_format('   ').text, '   ');
    expect(_format('2 bouées').text, '2 bouées');
    expect(_format('ßeta').text, 'ßeta');
  });

  test('attend la fin d’une saisie en cours du clavier', () {
    expect(
      _format('bou', composing: const TextRange(start: 0, end: 3)).text,
      'bou',
    );
  });
}
