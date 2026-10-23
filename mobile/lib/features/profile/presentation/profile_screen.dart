import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/theme.dart';
import '../data/profile_service.dart';
import '../data/boat_profile_loader.dart';
import 'boat_screen.dart';
import 'profile_panel.dart';
import 'profile_fields.dart';
import 'personal_information_screen.dart';
import '../domain/user_profile.dart';
import '../../../core/notifications/notification_permission.dart';

/// Enregistre une ou plusieurs préférences et renvoie le profil à jour.
typedef UpdatePreferences = Future<UserProfile> Function({
  bool? showUserName,
  bool? showBoatInfo,
  bool? notificationsEnabled,
});

/// Profil de l'utilisateur, ses préférences et la déconnexion.
///
/// Un interrupteur change tout de suite à l'écran, puis revient en arrière si
/// le backend refuse. Le statut de l'autorisation du téléphone est relu à
/// chaque retour dans l'app.
class ProfileScreen extends StatefulWidget {
  final ProfileService? profileService;
  final ValueChanged<UserProfile>? onProfileUpdated;
  final Future<void> Function()? onDeleteAccount;
  final UserProfile profile;
  final Future<void> Function() onSignOut;
  final UpdatePreferences onUpdatePreferences;
  final NotificationPermissionService notificationPermissions;

  const ProfileScreen({
    super.key,
    this.profileService,
    this.onProfileUpdated,
    this.onDeleteAccount,
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
  BoatProfileLoader? _boatLoader;
  bool _isSaving = false;
  NotificationPermission? _permission;
  String? _buildLabel;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    if (widget.profileService case final service?) {
      _boatLoader = BoatProfileLoader(service);
      // Une panne de préchargement ne bloque pas le profil ; le bateau
      // proposera une nouvelle tentative à son ouverture.
      unawaited(
        _boatLoader!.load().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    unawaited(_loadPermission());
    unawaited(_loadBuildLabel());
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(_loadPermission()),
    );
  }

  Future<void> _loadBuildLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(
          () => _buildLabel = 'NoWave ${info.version} · ${info.buildNumber}',
        );
      }
    } catch (_) {
      // La version reste facultative si le plugin est indisponible.
    }
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

  Future<void> _signOut() async {
    await widget.onSignOut();
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

  /// Préférence activée : on demande l'autorisation si iOS/Android peut encore
  /// l'afficher, sinon on ouvre les réglages du téléphone.
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

  Future<void> _openPersonalInformation() async {
    final service = widget.profileService;
    if (service == null) return;
    final updated = await Navigator.of(context).push<UserProfile>(
      profilePanelRoute(
        (_) => PersonalInformationScreen(profile: _profile, service: service),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _profile = updated);
    widget.onProfileUpdated?.call(updated);
  }

  Future<void> _openAccountManagement() => Navigator.of(context).push<void>(
    profilePanelRoute(
      (context) => ProfilePanel(
        title: 'Gestion du compte',
        onBack: () => Navigator.of(context).pop(),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.onDeleteAccount != null)
              ProfileGroup(
                children: [
                  _ProfileLink(
                    icon: Icons.delete_outline,
                    title: 'Supprimer mon compte',
                    subtitle: 'Une confirmation vous sera demandée',
                    destructive: true,
                    onTap: widget.onDeleteAccount,
                  ),
                ],
              ),
            if (_buildLabel case final label?) ...[
              const SizedBox(height: 32),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFF526474)),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ProfilePanel(
    title: 'Mon profil',
    onClose: _isSaving ? null : () => Navigator.of(context).pop(),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 32).clamp(0, double.infinity),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: const Color(0xFFE0EDF1),
                        foregroundColor: AppColors.text,
                        child: Text(
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                          ),
                          _profile.username.isEmpty
                              ? '?'
                              : _profile.username.characters.first
                                    .toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _profile.username,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ProfileGroup(
                    children: [
                      _ProfileLink(
                        icon: Icons.person_outline,
                        title: 'Informations personnelles',
                        subtitle: 'Date de naissance, nationalité',
                        onTap: _isSaving || widget.profileService == null
                            ? null
                            : _openPersonalInformation,
                      ),
                      if (widget.profileService case final service?)
                        _ProfileLink(
                          icon: Icons.sailing_outlined,
                          title: 'Mon bateau',
                          onTap: _isSaving
                              ? null
                              : () => Navigator.of(context).push<void>(
                                  profilePanelRoute(
                                    (_) => BoatScreen(
                                      profileService: service,
                                      boatLoader: _boatLoader,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ProfileGroup(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: _PreferenceSwitch(
                              switchKey: const Key(
                                'notificationsEnabledSwitch',
                              ),
                              label: 'Alertes à proximité',
                              value: _profile.notificationsEnabled,
                              onChanged: _isSaving ? null : _onAlertsChanged,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              'GPS en arrière-plan pour les alertes. Peut consommer plus de batterie.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF526474),
                              ),
                            ),
                          ),
                          if (_permission case final permission?) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: _PermissionStatus(permission),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Visibilité',
                    style: TextStyle(fontSize: 12, color: Color(0xFF526474)),
                  ),
                  const SizedBox(height: 8),
                  ProfileGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _PreferenceSwitch(
                          switchKey: const Key('showUserNameSwitch'),
                          label: 'Afficher le nom d’utilisateur',
                          value: _profile.showUserName,
                          onChanged: _isSaving
                              ? null
                              : (value) =>
                                    _updatePreferences(showUserName: value),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _PreferenceSwitch(
                          switchKey: const Key('showBoatInfoSwitch'),
                          label: 'Afficher les informations du bateau',
                          value: _profile.showBoatInfo,
                          onChanged: _isSaving
                              ? null
                              : (value) =>
                                    _updatePreferences(showBoatInfo: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ProfileGroup(
                    children: [
                      _ProfileLink(
                        icon: Icons.manage_accounts_outlined,
                        title: 'Gestion du compte',
                        onTap: _isSaving ? null : _openAccountManagement,
                      ),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: [
                    TextButton.icon(
                      onPressed: _isSaving ? null : _signOut,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Se déconnecter'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ProfileLink extends StatelessWidget {
  const _ProfileLink({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(
      icon,
      color: destructive ? const Color(0xFFB91C1C) : AppColors.text,
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14,
        color: destructive ? const Color(0xFFB91C1C) : AppColors.text,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: const TextStyle(fontSize: 11, color: Color(0xFF526474)),
          ),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
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
            style: const TextStyle(color: AppColors.text, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.cyan500,
          inactiveTrackColor: const Color(0xFFE1E7EA),
          inactiveThumbColor: const Color(0xFF81909C),
        ),
      ],
    ),
  );
}

/// Indique si le téléphone autorise vraiment les notifications.
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
        style: const TextStyle(color: Color(0xFF526474), fontSize: 12),
      ),
    );
  }
}
