import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Progression d'un parcours en plusieurs pages : l'inscription (e-mail, mot
/// de passe, vérification), puis le premier passage du profil (nom
/// d'utilisateur, type de bateau, nom et pavillon, visibilité, alertes).
class OnboardingProgress extends StatelessWidget {
  /// Étape affichée, de 1 à [stepCount].
  final int step;
  final int stepCount;

  const OnboardingProgress({
    super.key,
    required this.step,
    required this.stepCount,
  });

  @override
  Widget build(BuildContext context) {
    final label = 'Étape $step sur $stepCount';

    // Voile sombre derrière la progression : elle reste lisible sur le ciel
    // clair du haut des photos.
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.slate900.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 1; i <= stepCount; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= step
                            ? AppColors.cyan500
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
