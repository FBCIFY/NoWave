import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../../auth/presentation/widgets/auth_primary_button.dart';

/// Explique les alertes avant d'afficher la demande d'autorisation du téléphone.
class AlertsOnboardingScreen extends StatefulWidget {
  final Future<void> Function() onEnableAlerts;
  final VoidCallback onDone;
  final NotificationPermissionService notificationPermissions;

  const AlertsOnboardingScreen({
    super.key,
    required this.onEnableAlerts,
    required this.onDone,
    required this.notificationPermissions,
  });

  @override
  State<AlertsOnboardingScreen> createState() => _AlertsOnboardingScreenState();
}

class _AlertsOnboardingScreenState extends State<AlertsOnboardingScreen> {
  bool _isLoading = false;

  Future<void> _enableAlerts() async {
    setState(() => _isLoading = true);

    try {
      await widget.onEnableAlerts();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’activer les alertes. Réessayez.'),
        ),
      );
      return;
    }

    try {
      await widget.notificationPermissions.request();
    } catch (_) {
      // La préférence est enregistrée : l'autorisation reste modifiable
      // depuis le profil.
    }

    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Alertes à proximité',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.cyan500, AppColors.blue600],
                ),
              ),
              child: const Icon(
                Icons.notifications_active_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Des alertes quand un danger est proche',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'NoWave vous prévient quand un danger est signalé près de vous '
            'en mer. Pour cela, l’app a besoin de vous envoyer des '
            'notifications.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vous pourrez changer d’avis à tout moment dans votre profil.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 28),
          AuthPrimaryButton(
            label: 'Activer les alertes',
            onPressed: _isLoading ? null : _enableAlerts,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : widget.onDone,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.45),
            ),
            child: const Text('Plus tard'),
          ),
        ],
      ),
    );
  }
}
