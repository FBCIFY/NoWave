import 'package:flutter/material.dart';

import '../../../core/device/device_position_reporter.dart';
import '../../../core/device/device_registration.dart';
import '../../../core/device/device_position_tracker.dart';
import '../../../core/device/device_registrar.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/widgets/flow_transition.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../home/presentation/home_screen.dart';
import '../../map/data/report_tiles.dart';
import '../data/profile_service.dart';
import '../domain/user_profile.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import 'alerts_onboarding_screen.dart';
import 'profile_setup_screen.dart';

/// Second aiguillage, une fois l'e-mail vérifié : charge le profil puis
/// affiche la création du profil, l'écran d'alertes (une seule fois, juste
/// après la création) ou l'accueil.
///
/// Garde aussi le dernier profil modifié pour que l'accueil reste à jour.
class ProfileGate extends StatefulWidget {
  final AuthService authService;
  final ProfileService profileService;
  final ManualReportService reportService;
  final PositionEstimateService positionEstimateService;
  final ReportTiles reportTiles;
  final ReportDetailService reportDetailService;
  final DeviceRegistration deviceRegistration;
  final DevicePositionReporter devicePositionReporter;

  const ProfileGate({
    super.key,
    required this.authService,
    required this.profileService,
    required this.reportService,
    required this.positionEstimateService,
    required this.reportTiles,
    required this.reportDetailService,
    required this.deviceRegistration,
    required this.devicePositionReporter,
  });

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<UserProfile?> _profileFuture;
  bool _profileWasJustCreated = false;
  UserProfile? _latestProfile;
  bool _showAlertsOnboarding = false;
  Future<void>? _signingOut;

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.profileService.getCurrentProfile();
  }

  void _reloadProfile() {
    setState(() {
      _profileWasJustCreated = true;
      _latestProfile = null;
      _profileFuture = widget.profileService.getCurrentProfile();
    });
  }

  /// Seul chemin qui affiche l'écran d'alertes : les comptes existants ne le
  /// voient pas.
  void _onProfileCreated() {
    _showAlertsOnboarding = true;
    _reloadProfile();
  }

  Future<UserProfile> _updatePreferences({
    bool? showUserName,
    bool? showBoatInfo,
    bool? notificationsEnabled,
  }) async {
    final profile = await widget.profileService.updatePreferences(
      showUserName: showUserName,
      showBoatInfo: showBoatInfo,
      notificationsEnabled: notificationsEnabled,
    );

    if (mounted) {
      setState(() => _latestProfile = profile);
    }

    return profile;
  }

  /// Déconnexion : arrête le suivi du téléphone et le désactive côté backend
  /// tant que la session permet encore de l'appeler, puis la ferme. Un second
  /// appui pendant ce temps réutilise la déconnexion en cours.
  Future<void> _signOut() {
    return _signingOut ??= _runSignOut().whenComplete(() => _signingOut = null);
  }

  Future<void> _runSignOut() async {
    await widget.devicePositionReporter.stop();
    await widget.deviceRegistration.unregister();
    await widget.authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        late final int step;
        late final Widget screen;

        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_profileWasJustCreated) {
            step = 1;
            screen = ProfileSetupScreen(
              profileService: widget.profileService,
              onProfileCreated: _onProfileCreated,
              onSignOut: _signOut,
            );
          } else {
            step = 0;
            screen = const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
        } else if (snapshot.hasError) {
          step = 0;
          screen = Scaffold(
            appBar: AppBar(
              title: const Text('NoWave'),
              actions: [
                TextButton(
                  onPressed: _signOut,
                  child: const Text('Déconnexion'),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de récupérer votre profil.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reloadProfile,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else if (snapshot.data != null && _showAlertsOnboarding) {
          step = 2;
          screen = AlertsOnboardingScreen(
            onEnableAlerts: () =>
                _updatePreferences(notificationsEnabled: true),
            onDone: () => setState(() => _showAlertsOnboarding = false),
            notificationPermissions: const NotificationPermissionService(),
          );
        } else if (snapshot.data case final profile?) {
          step = 3;
          // Le profil existe : le backend accepte l'enregistrement du téléphone
          // et sa position.
          screen = DeviceRegistrar(
            registration: widget.deviceRegistration,
            child: DevicePositionTracker(
              reporter: widget.devicePositionReporter,
              child: HomeScreen(
                profile: _latestProfile ?? profile,
                onSignOut: _signOut,
                onUpdatePreferences: _updatePreferences,
                reportService: widget.reportService,
                positionEstimateService: widget.positionEstimateService,
                reportTiles: widget.reportTiles,
                reportDetailService: widget.reportDetailService,
              ),
            ),
          );
        } else {
          step = 1;
          screen = ProfileSetupScreen(
            profileService: widget.profileService,
            onProfileCreated: _onProfileCreated,
            onSignOut: _signOut,
          );
        }

        return FlowTransition(step: step, child: screen);
      },
    );
  }
}
