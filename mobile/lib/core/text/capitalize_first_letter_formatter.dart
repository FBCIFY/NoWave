import 'package:flutter/services.dart';

/// Met en majuscule la première lettre saisie, même si l'utilisateur coupe la
/// majuscule du clavier ou colle du texte. À associer à
/// [TextCapitalization.sentences] pour que le clavier s'ouvre en majuscule.
class CapitalizeFirstLetterFormatter extends TextInputFormatter {
  const CapitalizeFirstLetterFormatter();

  static final _firstVisible = RegExp(r'\S');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Pendant une saisie en cours (suggestions du clavier Android), modifier
    // le texte perturbe le clavier : la correction attend la fin du mot.
    if (!newValue.composing.isCollapsed) return newValue;

    final text = newValue.text;
    final index = text.indexOf(_firstVisible);
    if (index < 0) return newValue;

    final first = text[index];
    final upper = first.toUpperCase();
    // Garde la position du curseur : on ne remplace que si la longueur ne
    // change pas (« ß » deviendrait « SS »).
    if (upper == first || upper.length != first.length) return newValue;

    return newValue.copyWith(text: text.replaceRange(index, index + 1, upper));
  }
}
