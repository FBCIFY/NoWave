import 'package:flutter/foundation.dart';

/// Étapes de l'arrivée sur la carte à la fin de l'onboarding.
enum MapIntroPhase {
  /// La carte se charge sous l'onboarding.
  covered,

  /// Onboarding terminé : la carte demande la position pendant que la photo
  /// reste affichée.
  starting,

  /// L'onboarding s'efface en fondu, puis la carte vole jusqu'à
  /// l'utilisateur.
  revealed,
}

/// Arrivée sur la carte à la fin de l'onboarding : la carte se charge
/// dessous dès la création du profil, sans écran blanc au passage, puis part
/// du globe pour descendre jusqu'à l'utilisateur.
class MapIntroController extends ChangeNotifier {
  /// Fondu de l'onboarding ; le vol commence à sa fin.
  static const fadeDuration = Duration(milliseconds: 1000);

  MapIntroPhase _phase = MapIntroPhase.covered;
  bool _attached = false;

  MapIntroPhase get phase => _phase;

  /// La carte est encore cachée par l'onboarding.
  bool get covered => _phase != MapIntroPhase.revealed;

  /// Une carte prépare l'arrivée : c'est elle qui appellera [reveal].
  void attach() => _attached = true;

  /// La carte disparaît. Sans notification : appelé pendant son `dispose`.
  void detach() => _attached = false;

  /// Fin de l'onboarding. Sans carte pour préparer l'arrivée, l'onboarding
  /// s'efface tout de suite.
  void start() {
    if (_phase != MapIntroPhase.covered) return;
    _phase = _attached ? MapIntroPhase.starting : MapIntroPhase.revealed;
    notifyListeners();
  }

  /// La carte est prête : l'onboarding peut s'effacer.
  void reveal() {
    if (_phase == MapIntroPhase.revealed) return;
    _phase = MapIntroPhase.revealed;
    notifyListeners();
  }
}
