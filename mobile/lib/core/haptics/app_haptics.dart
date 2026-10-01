import 'dart:async';

import 'package:flutter/services.dart';

/// Vibrations de l'app, réservées aux moments où l'on regarde peu l'écran :
/// sur l'eau, avec des gants ou en plein soleil. Les boutons ordinaires n'en
/// ont pas : à chaque appui, la vibration deviendrait du bruit.
abstract final class AppHaptics {
  /// Choix d'une catégorie, boutons boussole et recentrage.
  static void selection() => unawaited(HapticFeedback.selectionClick());

  /// Prise de la photo : l'obturateur ne s'entend pas dans le vent.
  static void capture() => unawaited(HapticFeedback.lightImpact());

  /// Signalement publié, avec sa photo s'il en a une.
  static void success() => unawaited(HapticFeedback.mediumImpact());

  /// Publication ou envoi de la photo en échec : il faut regarder l'écran.
  static void failure() => unawaited(HapticFeedback.heavyImpact());
}
