import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'sign_out_dialog.dart';
import 'suspended_account_screen.dart';

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
  final ValueListenable<int>? inactiveUserEvents;

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
    this.inactiveUserEvents,
  });

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> with WidgetsBindingObserver {
  late Future<UserProfile?> _profileFuture;
  bool _profileWasJustCreated = false;
  UserProfile? _latestProfile;
  bool _showAlertsOnboarding = false;
  Future<void>? _signingOut;
  bool _accessRevoked = false;
  bool _refreshingAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.inactiveUserEvents?.addListener(_markAccessRevoked);
    _profileFuture = widget.profileService.getCurrentProfile();
  }

  @override
  void didUpdateWidget(covariant ProfileGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.inactiveUserEvents != widget.inactiveUserEvents) {
      oldWidget.inactiveUserEvents?.removeListener(_markAccessRevoked);
      widget.inactiveUserEvents?.addListener(_markAccessRevoked);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAccessStatus());
    }
  }

  @override
  void dispose() {
    widget.inactiveUserEvents?.removeListener(_markAccessRevoked);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _markAccessRevoked() {
    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);

    setState(() {
      _accessRevoked = true;
    });
  }

  Future<void> _refreshAccessStatus() async {
    if (_refreshingAccess) return;

    _refreshingAccess = true;

    try {
      final profile = await widget.profileService.getCurrentProfile();

      if (!mounted) return;

      setState(() {
        _accessRevoked = profile?.status == 'suspended';
        _latestProfile = profile;
        _profileFuture = Future<UserProfile?>.value(profile);
      });
    } catch (_) {
      // En cas de panne réseau, conserver l'état courant.
    } finally {
      _refreshingAccess = false;
    }
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
  ///
  /// [resumeDevices] : la déconnexion part de l'accueil, où l'enregistrement
  /// et le GPS tournent et doivent reprendre si l'utilisateur annule.
  Future<void> _signOut({bool resumeDevices = false}) {
    return _signingOut ??= showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SignOutDialog(
        onSignOut: _runSignOut,
        onCancel: () => _cancelSignOut(resumeDevices: resumeDevices),
      ),
    ).whenComplete(() => _signingOut = null);
  }

  /// Échec puis « Annuler » : on reste sur ce compte. Hors de l'accueil, rien
  /// ne tourne encore : `DeviceRegistrar` démarrera à l'arrivée sur l'accueil.
  void _cancelSignOut({required bool resumeDevices}) {
    widget.deviceRegistration.cancelSignOut();
    if (!resumeDevices) return;
    unawaited(widget.deviceRegistration.start());
    unawaited(widget.devicePositionReporter.start());
  }

  Future<void> _runSignOut() async {
    widget.deviceRegistration.beginSignOut();
    await widget.devicePositionReporter.stop();
    await widget.deviceRegistration.unregister();
    await widget.authService.signOut();
    widget.deviceRegistration.completeSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        late final int step;
        late final Widget screen;

        if (_accessRevoked || snapshot.data?.status == 'suspended') {
          step = 4;
          screen = SuspendedAccountScreen(
            onSignOut: () => unawaited(_signOut()),
          );
        } else if (snapshot.connectionState == ConnectionState.waiting) {
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
                onUserInactive: () => unawaited(_refreshAccessStatus()),
                onSignOut: () => _signOut(resumeDevices: true),
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
