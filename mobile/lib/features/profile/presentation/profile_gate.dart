import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/device/device_position_reporter.dart';
import '../../../core/device/device_position_tracker.dart';
import '../../../core/device/device_registrar.dart';
import '../../../core/device/device_registration.dart';
import '../../../core/notifications/alert_push_controller.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../alerts/data/alert_service.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/presentation/widgets/flow_transition.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../home/presentation/home_screen.dart';
import '../../map/data/report_tiles.dart';
import '../../map/presentation/map_intro_controller.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import '../data/account_deletion.dart';
import '../data/profile_service.dart';
import '../domain/user_profile.dart';
import 'account_deletion_screen.dart';
import 'profile_onboarding_screen.dart';
import 'sign_out_dialog.dart';
import 'suspended_account_screen.dart';

/// Second aiguillage, une fois l'e-mail vérifié : charge le profil puis
/// affiche le premier passage ([ProfileOnboardingScreen] : création du profil,
/// puis bateau, visibilité et alertes, une seule fois, juste après la
/// création) ou l'accueil.
///
/// Garde aussi le dernier profil modifié pour que l'accueil reste à jour.
class ProfileGate extends StatefulWidget {
  final AuthService authService;
  final AlertService? alertService;
  final AlertPushController? pushController;
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
    this.alertService,
    this.pushController,
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
  UserProfile? _latestProfile;
  bool _showOnboarding = false;

  /// Arrivée sur la carte, créée avec le profil : l'accueil se charge alors
  /// sous la suite de l'onboarding.
  MapIntroController? _intro;
  Future<void>? _signingOut;
  bool _accessRevoked = false;
  bool _refreshingAccess = false;
  bool _deletingAccount = false;
  bool _deletionChecked = false;
  late final AccountDeletion _accountDeletion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.inactiveUserEvents?.addListener(_markAccessRevoked);
    _accountDeletion = AccountDeletion(
      profileService: widget.profileService,
      authService: widget.authService,
      registration: widget.deviceRegistration,
      reporter: widget.devicePositionReporter,
    );
    _profileFuture = _loadInitialProfile();
  }

  Future<UserProfile?> _loadInitialProfile() async {
    final pending = await _accountDeletion.restore();
    if (!mounted) return null;

    _deletionChecked = true;

    if (pending) {
      widget.pushController?.setReady(false);
      setState(() => _deletingAccount = true);
      return null;
    }

    return widget.profileService.getCurrentProfile();
  }

  Future<void> _openAccountDeletion() async {
    widget.pushController?.setReady(false);
    Navigator.of(context).popUntil((route) => route.isFirst);

    if (!mounted) return;
    setState(() => _deletingAccount = true);
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
    _intro?.dispose();
    super.dispose();
  }

  void _markAccessRevoked() {
    if (!mounted || _deletingAccount) return;

    widget.pushController?.setReady(false);
    Navigator.of(context).popUntil((route) => route.isFirst);

    setState(() {
      _accessRevoked = true;
    });
  }

  Future<void> _refreshAccessStatus() async {
    if (_refreshingAccess || _deletingAccount || !_deletionChecked) return;

    _refreshingAccess = true;

    try {
      final profile = await widget.profileService.getCurrentProfile();

      if (!mounted || _deletingAccount) return;

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
      _latestProfile = null;
      _profileFuture = _loadInitialProfile();
    });
  }

  /// Seul chemin qui affiche la suite du premier passage (bateau, visibilité,
  /// alertes) : les comptes existants ne la voient pas. Le profil renvoyé
  /// suffit, sans relecture : le parcours continue sur le même écran.
  void _onProfileSaved(UserProfile profile) {
    // Un nouveau nom sur la même page garde l'arrivée déjà en préparation.
    if (_intro?.covered != true) {
      _intro?.dispose();
      _intro = MapIntroController()..addListener(_handleIntro);
    }
    setState(() {
      _showOnboarding = true;
      _latestProfile = profile;
      _profileFuture = Future<UserProfile?>.value(profile);
    });
  }

  void _handleIntro() {
    if (mounted) setState(() {});
  }

  /// Fin du fondu : l'onboarding quitte l'arbre, l'accueil reste en place.
  void _endOnboarding() {
    if (!mounted || (_intro?.covered ?? true) || !_showOnboarding) return;
    setState(() => _showOnboarding = false);
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
    widget.pushController?.setReady(false);
    return _signingOut ??=
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SignOutDialog(
            onSignOut: _runSignOut,
            onCancel: () => _cancelSignOut(resumeDevices: resumeDevices),
          ),
        ).whenComplete(() {
          _signingOut = null;
          if (mounted &&
              !widget.deviceRegistration.isSigningOut &&
              !_accessRevoked &&
              !_deletingAccount) {
            widget.pushController?.setReady(resumeDevices);
          }
        });
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
        widget.pushController?.setReady(
          !_deletingAccount &&
              !_accessRevoked &&
              (snapshot.connectionState == ConnectionState.done ||
                  snapshot.hasData) &&
              !snapshot.hasError &&
              snapshot.data?.status == 'active' &&
              !_showOnboarding &&
              _signingOut == null,
        );
        late final int step;
        late final Widget screen;

        if (_deletingAccount) {
          step = 6;
          screen = AccountDeletionScreen(
            deletion: _accountDeletion,
            onCancel: () => setState(() => _deletingAccount = false),
            onDone: () {
              if (!mounted) return;
              widget.pushController?.setReady(false);
              setState(() {
                _latestProfile = null;
              });
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          );
        } else if (_accessRevoked || snapshot.data?.status == 'suspended') {
          step = 5;
          screen = SuspendedAccountScreen(
            onSignOut: () => unawaited(_signOut()),
            onDeleteAccount: () => unawaited(_openAccountDeletion()),
          );
        } else if (_showOnboarding ||
            (_intro != null && (_latestProfile ?? snapshot.data) != null)) {
          // Même étape que sans profil : le parcours garde son état et seules
          // ses pages glissent. L'accueil, chargé dessous, reste sur cette
          // étape après le fondu pour ne pas recréer la carte.
          step = 1;
          screen = _buildFirstVisit(_latestProfile ?? snapshot.data);
        } else if (snapshot.connectionState == ConnectionState.waiting &&
            // Rafraîchi au retour dans l'app : le profil affiché reste à
            // l'écran. Recréer l'accueil relancerait la carte, et l'ancien
            // suivi GPS arrêterait le nouveau en disparaissant.
            !snapshot.hasData) {
          step = 0;
          screen = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
        } else if (snapshot.data case final profile?) {
          step = 4;
          screen = _buildHome(_latestProfile ?? profile);
        } else {
          step = 1;
          screen = _buildFirstVisit(null);
        }

        return FlowTransition(step: step, child: screen);
      },
    );
  }

  /// Le profil existe : le backend accepte l'enregistrement du téléphone et
  /// sa position. Avec [active] faux, l'accueil se charge sans rien démarrer.
  Widget _buildHome(
    UserProfile profile, {
    bool active = true,
    MapIntroController? intro,
  }) {
    return DeviceRegistrar(
      registration: widget.deviceRegistration,
      active: active,
      child: DevicePositionTracker(
        reporter: widget.devicePositionReporter,
        runInBackground: profile.notificationsEnabled,
        active: active,
        child: HomeScreen(
          alertService: widget.alertService,
          pushController: widget.pushController,
          profileService: widget.profileService,
          onDeleteAccount: _openAccountDeletion,
          profile: profile,
          onUserInactive: () => unawaited(_refreshAccessStatus()),
          onSignOut: () => _signOut(resumeDevices: true),
          onUpdatePreferences: _updatePreferences,
          reportService: widget.reportService,
          positionEstimateService: widget.positionEstimateService,
          reportTiles: widget.reportTiles,
          reportDetailService: widget.reportDetailService,
          intro: intro,
        ),
      ),
    );
  }

  /// Premier passage : l'onboarding, puis, dès le profil créé, l'accueil qui
  /// se charge dessous. À la fin, l'onboarding s'efface sur la carte. Les clés
  /// gardent l'état de chacun quand l'autre apparaît ou disparaît.
  Widget _buildFirstVisit(UserProfile? profile) {
    final intro = _intro;
    final showHome = intro != null && profile != null;
    final covered = intro?.covered ?? true;
    final fading = showHome && !covered;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showHome)
          KeyedSubtree(
            key: const ValueKey('home'),
            child: IgnorePointer(
              ignoring: covered,
              child: ExcludeSemantics(
                excluding: covered,
                child: _buildHome(profile, active: !covered, intro: intro),
              ),
            ),
          ),
        if (!showHome || _showOnboarding)
          KeyedSubtree(
            key: const ValueKey('onboarding'),
            child: IgnorePointer(
              ignoring: fading,
              child: ExcludeSemantics(
                excluding: fading,
                child: AnimatedOpacity(
                  opacity: fading ? 0 : 1,
                  duration: MapIntroController.fadeDuration,
                  curve: Curves.easeOut,
                  onEnd: _endOnboarding,
                  child: _buildOnboarding(profile),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOnboarding(UserProfile? profile) {
    return ProfileOnboardingScreen(
      profile: profile,
      profileService: widget.profileService,
      onProfileSaved: _onProfileSaved,
      onUpdatePreferences: _updatePreferences,
      notificationPermissions: const NotificationPermissionService(),
      onSignOut: _signOut,
      onDone: () {
        final intro = _intro;
        if (intro != null) {
          intro.start();
        } else {
          setState(() => _showOnboarding = false);
        }
      },
    );
  }
}
