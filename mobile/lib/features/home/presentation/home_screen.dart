import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/notifications/alert_push_controller.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/notifications/push_notification_listener.dart';
import '../../alerts/data/alert_read_store.dart';
import '../../alerts/data/alert_service.dart';
import '../../alerts/data/unread_alert_recovery.dart';
import '../../alerts/domain/alert.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../camera/domain/photo_report_draft.dart';
import '../../camera/presentation/camera_screen.dart';
import '../../map/data/report_tiles.dart';
import '../../map/presentation/map_intro_controller.dart';
import '../../map/presentation/map_screen.dart';
import '../../profile/data/profile_service.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import '../../reports/domain/report_detail.dart';

/// Accueil après connexion : la carte, avec un bouton qui ouvre le profil.
class HomeScreen extends StatefulWidget {
  final ProfileService? profileService;
  final Future<void> Function()? onDeleteAccount;
  final UserProfile? profile;
  final AlertService? alertService;
  final AlertPushController? pushController;
  final Future<void> Function()? onSignOut;
  final UpdatePreferences? onUpdatePreferences;
  final ManualReportService? reportService;
  final PositionEstimateService? positionEstimateService;
  final ReportTiles? reportTiles;
  final ReportDetailService? reportDetailService;
  final VoidCallback? onUserInactive;

  /// Arrivée sur la carte à la fin de l'onboarding, transmise à [MapScreen].
  final MapIntroController? intro;

  const HomeScreen({
    super.key,
    this.profileService,
    this.onDeleteAccount,
    this.alertService,
    this.pushController,
    this.profile,
    this.onSignOut,
    this.onUpdatePreferences,
    this.reportService,
    this.positionEstimateService,
    this.reportTiles,
    this.reportDetailService,
    this.onUserInactive,
    this.intro,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final MapFocusController _mapFocusController = MapFocusController(
    onReportOpened: (id) => unawaited(_alertRecovery?.markOpened(id)),
  );
  UnreadAlertRecovery? _alertRecovery;
  int _pushRequest = 0;

  /// Pavillon du bateau pour le mât du curseur, relu au retour du profil
  /// où il a pu changer.
  final ValueNotifier<String?> _boatFlag = ValueNotifier(null);
  int _boatFlagRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configureAlertRecovery();
    _watchIntro(widget.intro);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intro != widget.intro) {
      oldWidget.intro?.removeListener(_handleIntro);
      _watchIntro(widget.intro);
    }
    if (oldWidget.profile?.id != widget.profile?.id ||
        oldWidget.profile?.notificationsEnabled !=
            widget.profile?.notificationsEnabled ||
        oldWidget.alertService != widget.alertService ||
        oldWidget.reportDetailService != widget.reportDetailService) {
      _configureAlertRecovery();
    }
  }

  void _configureAlertRecovery() {
    _alertRecovery?.dispose();
    _alertRecovery = null;
    final profile = widget.profile;
    final alerts = widget.alertService;
    final reports = widget.reportDetailService;
    if (profile == null ||
        !profile.notificationsEnabled ||
        alerts == null ||
        reports == null) {
      return;
    }
    _alertRecovery = UnreadAlertRecovery(
      alerts: alerts,
      reports: reports,
      readStore: AlertReadStore(accountId: profile.id),
      onUnread: _mapFocusController.showNotification,
      canReceive: () => mounted && (widget.pushController?.ready ?? true),
    );
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _alertRecovery!.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _alertRecovery?.start();
    } else {
      _alertRecovery?.pause();
    }
  }

  void _receiveAlert(AlertPush push) {
    final recovery = _alertRecovery;
    if (recovery != null) {
      unawaited(recovery.receive(push));
      return;
    }
    _mapFocusController.showNotification((
      id: push.alert.reportId,
      latitude: push.alert.latitude,
      longitude: push.alert.longitude,
      category: push.alert.category,
      expiresAt: push.expiresAt,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertRecovery?.dispose();
    _pushRequest++;
    _boatFlagRequest++;
    widget.intro?.removeListener(_handleIntro);
    _mapFocusController.dispose();
    _boatFlag.dispose();
    super.dispose();
  }

  /// Sous l'onboarding, le bateau n'est pas encore créé : il est lu à la fin
  /// du parcours.
  void _watchIntro(MapIntroController? intro) {
    if (intro?.phase == MapIntroPhase.covered) {
      intro!.addListener(_handleIntro);
    } else {
      _loadBoatFlag();
    }
  }

  void _handleIntro() {
    final intro = widget.intro;
    if (intro == null || intro.phase == MapIntroPhase.covered) return;
    intro.removeListener(_handleIntro);
    _loadBoatFlag();
  }

  Future<void> _loadBoatFlag() async {
    final service = widget.profileService;
    if (service == null) return;
    final request = ++_boatFlagRequest;
    try {
      final boat = await service.getBoat();
      if (!mounted || request != _boatFlagRequest) return;
      _boatFlag.value = boat?.flagCountry;
    } catch (_) {
      // Hors ligne ou serveur indisponible : le mât garde son pavillon.
    }
  }

  /// A push selects the main map; only the API supplies its actual position.
  Future<void> _openReportFromPush(String reportId) async {
    final request = ++_pushRequest;
    final controller = widget.pushController;
    final session = controller?.sessionEpoch;
    bool current() =>
        mounted &&
        request == _pushRequest &&
        (controller == null ||
            (controller.ready && controller.sessionEpoch == session));
    if (!current()) return;
    if (_mapFocusController.isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Terminez ou annulez votre signalement ; l’alerte sera ensuite affichée.',
          ),
        ),
      );
      await _mapFocusController.whenUnblocked;
      if (!current()) return;
    }
    if (!mounted) return;
    _mapFocusController.clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
    final service = widget.reportDetailService;
    if (service == null) {
      throw const AlertOpenFailure('Chargement du signalement indisponible.');
    }
    final ReportDetail report;
    try {
      report = await service.fetchReport(reportId);
    } catch (error) {
      if (!current()) return;
      if (error is ApiException && error.code == 'user_inactive') {
        widget.onUserInactive?.call();
      }
      if (error is ReportNotFoundException) {
        throw const AlertOpenFailure(
          'Ce signalement n’est plus disponible.',
          retryable: false,
        );
      }
      if (error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        throw const AlertOpenFailure(
          'Vous n’avez pas accès à ce signalement. Vérifiez votre session.',
          retryable: false,
        );
      }
      throw const AlertOpenFailure(
        'Impossible de charger le signalement. Vérifiez votre connexion.',
      );
    }
    if (!current()) return;
    if (!report.expiresAt.isAfter(DateTime.now())) {
      throw const AlertOpenFailure(
        'Ce signalement a expiré.',
        retryable: false,
      );
    }
    if (report.id != reportId ||
        !report.latitude.isFinite ||
        !report.longitude.isFinite ||
        report.latitude.abs() > 90 ||
        report.longitude.abs() > 180) {
      throw const AlertOpenFailure(
        'La position du signalement reçue est invalide.',
      );
    }
    if (_mapFocusController.isBlocked) {
      // The draft opened during HTTP. Wait without altering it, then re-read
      // the report rather than applying a potentially stale response.
      await _mapFocusController.whenUnblocked;
      if (current()) await _openReportFromPush(reportId);
      return;
    }
    try {
      await _mapFocusController.focusAlert(report, isCurrent: current);
    } on MapFocusBlocked {
      await _mapFocusController.whenUnblocked;
      if (current()) await _openReportFromPush(reportId);
    } on ReportNotFoundException {
      throw const AlertOpenFailure(
        'Ce signalement a expiré.',
        retryable: false,
      );
    }
  }

  /// Action « Historique » d'une notification : Mes alertes s'ouvre sur la
  /// carte principale.
  void _openAlerts() {
    if (!mounted ||
        widget.alertService == null ||
        widget.reportDetailService == null) {
      return;
    }
    if (_mapFocusController.isBlocked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez ou annulez votre signalement avant d’ouvrir vos alertes.',
            ),
          ),
        );
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    _mapFocusController.openAlerts();
  }

  @override
  Widget build(BuildContext context) {
    final positionEstimateService = widget.positionEstimateService;

    final map = MapScreen(
      focusController: _mapFocusController,
      intro: widget.intro,
      alertService: widget.reportDetailService == null
          ? null
          : widget.alertService,
      reportService: widget.reportService,
      reportTiles: widget.reportTiles,
      reportDetailService: widget.reportDetailService,
      onUserInactive: widget.onUserInactive,
      boatFlag: _boatFlag,
      // La caméra renvoie la photo et le point estimé, que la carte fait
      // confirmer avant publication.
      onOpenCamera: positionEstimateService == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<PhotoReportDraft>(
                fullscreenDialog: true,
                builder: (_) => CameraScreen(
                  positionEstimateService: positionEstimateService,
                ),
              ),
            ),
      onOpenProfile:
          widget.profile == null ||
              widget.onSignOut == null ||
              widget.onUpdatePreferences == null
          ? null
          : () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileScreen(
                        profile: widget.profile!,
                        profileService: widget.profileService,
                        onDeleteAccount: widget.onDeleteAccount,
                        onSignOut: widget.onSignOut!,
                        onUpdatePreferences: widget.onUpdatePreferences!,
                        notificationPermissions:
                            const NotificationPermissionService(),
                      ),
                    ),
                  )
                  .then((_) => _loadBoatFlag());
            },
    );

    final controller = widget.pushController;
    return controller == null
        ? map
        : PushNotificationListener(
            controller: controller,
            onReceived: _receiveAlert,
            onOpen: (push) => _openReportFromPush(push.alert.reportId),
            onOpenHistory: _openAlerts,
            child: map,
          );
  }
}
