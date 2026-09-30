import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../auth/presentation/widgets/auth_layout.dart';
import '../domain/user_profile.dart';
import '../../../core/notifications/notification_permission.dart';

typedef UpdatePreferences = Future<UserProfile> Function({
  bool? showUserName,
  bool? showBoatInfo,
  bool? notificationsEnabled,
});

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final Future<void> Function() onSignOut;
  final UpdatePreferences onUpdatePreferences;
  final NotificationPermissionService notificationPermissions;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onSignOut,
    required this.onUpdatePreferences,
    required this.notificationPermissions,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _profile;
  bool _isSaving = false;
  NotificationPermission? _permission;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    unawaited(_loadPermission());
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_loadPermission()),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _loadPermission() async {
    try {
      final permission = await widget.notificationPermissions.getStatus();
      if (!mounted) return;
      setState(() => _permission = permission);
    } catch (_) {
      // Sans réponse du téléphone, on n'affiche simplement pas l'état.
    }
  }

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

  Future<void> _signOut() async {
    await widget.onSignOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _updatePreferences({
    bool? showUserName,
    bool? showBoatInfo,
    bool? notificationsEnabled,
  }) async {
    final previousProfile = _profile;

    setState(() {
      _isSaving = true;
      _profile = previousProfile.copyWith(
        showUserName: showUserName,
        showBoatInfo: showBoatInfo,
        notificationsEnabled: notificationsEnabled,
      );
    });

    try {
      final updatedProfile = await widget.onUpdatePreferences(
        showUserName: showUserName,
        showBoatInfo: showBoatInfo,
        notificationsEnabled: notificationsEnabled,
      );
      if (!mounted) return;
      setState(() {
        _profile = updatedProfile;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = previousProfile;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’enregistrer la préférence. Réessayez.'),
        ),
      );
    }
  }

  Future<void> _onAlertsChanged(bool enabled) async {
    await _updatePreferences(notificationsEnabled: enabled);
    if (!enabled || !mounted || !_profile.notificationsEnabled) return;
    await _askPhonePermission();
  }

  Future<void> _askPhonePermission() async {
    final permissions = widget.notificationPermissions;
    try {
      switch (await permissions.getStatus()) {
        case NotificationPermission.granted:
          return;
        case NotificationPermission.notDetermined:
          final permission = await permissions.request();
          if (!mounted) return;
          setState(() => _permission = permission);
        case NotificationPermission.denied:
          await permissions.openSettings();
      }
    } catch (_) {
      // Si le téléphone ne répond pas, la préférence reste enregistrée.
    }
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
                  _profile.username.isEmpty
                      ? '?'
                      : _profile.username.substring(0, 1).toUpperCase(),
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
                      _profile.username,
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
                        value: _roleLabel(_profile.role),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Statut',
                        value: _statusLabel(_profile.status),
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
                        value: _formatDate(_profile.dateOfBirth),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ProfileDetail(
                        label: 'Nationalité',
                        value: _profile.nationality ?? 'Non renseignée',
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
                _PreferenceSwitch(
                  switchKey: const Key('showUserNameSwitch'),
                  label: 'Afficher le nom d’utilisateur',
                  value: _profile.showUserName,
                  onChanged: _isSaving
                      ? null
                      : (value) => _updatePreferences(showUserName: value),
                ),
                const _CardDivider(),
                _PreferenceSwitch(
                  switchKey: const Key('showBoatInfoSwitch'),
                  label: 'Afficher les informations du bateau',
                  value: _profile.showBoatInfo,
                  onChanged: _isSaving
                      ? null
                      : (value) => _updatePreferences(showBoatInfo: value),
                ),
                const _CardDivider(),
                _PreferenceSwitch(
                  switchKey: const Key('notificationsEnabledSwitch'),
                  label: 'Alertes à proximité',
                  value: _profile.notificationsEnabled,
                  onChanged: _isSaving ? null : _onAlertsChanged,
                ),
                if (_permission case final permission?) ...[
                  const SizedBox(height: 8),
                  _PermissionStatus(permission),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _signOut,
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

class _PreferenceSwitch extends StatelessWidget {
  final Key switchKey;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _PreferenceSwitch({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.cyan500,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
          inactiveThumbColor: Colors.white.withValues(alpha: 0.7),
        ),
      ],
    ),
  );
}

class _PermissionStatus extends StatelessWidget {
  final NotificationPermission permission;
  const _PermissionStatus(this.permission);

  @override
  Widget build(BuildContext context) {
    final label = switch (permission) {
      NotificationPermission.granted => 'Autorisées sur ce téléphone',
      NotificationPermission.denied =>
        'Bloquées dans les réglages du téléphone',
      NotificationPermission.notDetermined =>
        'Pas encore autorisées sur ce téléphone',
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
        ),
      ),
    );
  }
}
