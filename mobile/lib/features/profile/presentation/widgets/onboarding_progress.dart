import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Progression du premier passage : nom d'utilisateur, type de bateau, nom et
/// pavillon, visibilité, alertes.
class OnboardingProgress extends StatelessWidget {
  static const stepCount = 5;

  /// Étape affichée, de 1 à [stepCount].
  final int step;

  const OnboardingProgress({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final label = 'Étape $step sur $stepCount';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= stepCount; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
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
    );
  }
}
