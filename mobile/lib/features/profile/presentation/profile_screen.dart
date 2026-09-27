import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../domain/user_profile.dart';

class ProfileScreen extends StatelessWidget {
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  String _formatDate(DateTime? date) {
    if (date == null) return 'Non renseignée';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String _roleLabel(String role) => switch (role) {
    'user' => 'Utilisateur',
    'admin' => 'Administrateur',
    _ => role,
  };

  String _statusLabel(String status) => switch (status) {
    'active' => 'Actif',
    'suspended' => 'Suspendu',
    _ => status,
  };

  Future<void> _signOut(BuildContext context) async {
    await onSignOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Mon profil',
      showBackButton: true,
      centerContent: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), AppColors.blue600],
                  ),
                ),
                child: Text(
                  profile.username.isEmpty
                      ? '?'
                      : profile.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Votre compte NoWave',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Informations du profil'),
          const SizedBox(height: 10),
          _ProfileCard(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Rôle',
                        value: _roleLabel(profile.role),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Statut',
                        value: _statusLabel(profile.status),
                      ),
                    ),
                  ],
                ),
                const _CardDivider(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Date de naissance',
                        value: _formatDate(profile.dateOfBirth),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Nationalité',
                        value: profile.nationality ?? 'Non renseignée',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Préférences'),
          const SizedBox(height: 10),
          _ProfileCard(
            child: Column(
              children: [
                _PreferenceRow(
                  label: 'Afficher le nom d’utilisateur',
                  enabled: profile.showUserName,
                ),
                const _CardDivider(),
                _PreferenceRow(
                  label: 'Afficher les informations du bateau',
                  enabled: profile.showBoatInfo,
                ),
                const _CardDivider(),
                _PreferenceRow(
                  label: 'Notifications activées',
                  enabled: profile.notificationsEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Se déconnecter'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    style: TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  final Widget child;
  const _ProfileCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: child,
  );
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
  );
}

class _ProfileDetail extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _PreferenceRow extends StatelessWidget {
  final String label;
  final bool enabled;
  const _PreferenceRow({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.cyan500.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          enabled ? 'Oui' : 'Non',
          style: TextStyle(
            color: enabled
                ? const Color(0xFF67E8F9)
                : Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
