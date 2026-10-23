import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// La carte reste visible entre les panneaux, sans recréer Mapbox.
Route<T> profilePanelRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  opaque: false,
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation,
        child: FadeTransition(
          opacity: ReverseAnimation(secondaryAnimation),
          child: child,
        ),
      ),
  transitionDuration: const Duration(milliseconds: 180),
);

/// Fond blanc translucide et marges sûres, sur iOS comme sur Android.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.onClose,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          media.padding.top + 48,
          12,
          math.max(12, media.padding.bottom),
        ),
        child: Material(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        tooltip: 'Retour',
                        onPressed: onBack,
                        icon: const Icon(Icons.chevron_left),
                      )
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onClose != null)
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      )
                    else
                      const SizedBox(height: 48, width: 8),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
