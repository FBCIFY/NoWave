import 'package:flutter/material.dart';

/// Route entre deux écrans `AuthPhotoLayout` : fondu au lieu du glissement.
///
/// Les deux écrans ont la même photo. En glissant, celui qui part emportait
/// sa photo et son voile sombre par-dessus l'autre, comme un filtre gris
/// posé sur la moitié de l'écran. En fondu, seuls le titre et le formulaire
/// changent.
class AuthPhotoRoute<T> extends PageRouteBuilder<T> {
  AuthPhotoRoute({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            ),
      );
}
