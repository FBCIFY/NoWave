import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Mise en page sombre commune aux écrans d'authentification et de profil :
/// fond dégradé, titre, bouton retour facultatif et contenu défilant.
class AuthLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBackButton;
  final bool centerContent;
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBackButton = false,
    this.centerContent = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.slate900,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.slate900,
                  AppColors.blue950,
                  AppColors.slate900,
                ],
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 320,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan500.withValues(alpha: 0.08),
                      blurRadius: 100,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                if (showBackButton)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed:
                                onBack ?? () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.10,
                              ),
                              foregroundColor: Colors.white.withValues(
                                alpha: 0.70,
                              ),
                            ),
                            icon: const Icon(Icons.arrow_back, size: 18),
                            tooltip: 'Retour',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            child: Align(
                              alignment: centerContent
                                  ? Alignment.center
                                  : Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!showBackButton) ...[
                                      Text(
                                        title,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (subtitle != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          subtitle!,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.35,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 32),
                                    ],
                                    child,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
