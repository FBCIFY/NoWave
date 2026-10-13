import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/notifications/alert_push_controller.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/notifications/push_notification_listener.dart';
import '../../alerts/data/alert_service.dart';
import '../../alerts/presentation/alert_report_screen.dart';
import '../../alerts/presentation/alerts_screen.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../camera/domain/photo_report_draft.dart';
import '../../camera/presentation/camera_screen.dart';
import '../../map/data/report_tiles.dart';
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
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapFocusController _mapFocusController = MapFocusController();

  @override
  void dispose() {
    _mapFocusController.dispose();
    super.dispose();
  }

  Future<void> _openReport(String reportId) async {
    final service = widget.reportDetailService;
    if (service == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlertReportScreen(
          reportId: reportId,
          service: service,
          onShowOnMap: _showReportOnMainMap,
        ),
      ),
    );
  }

  /// Un tap explicite sur une nouvelle notification ouvre immédiatement
  /// sa fiche, même si une autre fiche d'alerte est déjà affichée.
  Future<void> _openReportFromPush(String reportId) {
    unawaited(_openReport(reportId));
    return Future<void>.value();
  }

  /// Le détail vient d'être relu auprès du backend par AlertReportScreen.
  /// On revient à la route principale puis on pilote la MapScreen existante.
  Future<void> _showReportOnMainMap(ReportDetail report) async {
    if (!mounted) return;

    if (!_mapFocusController.focus(report)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez ou annulez votre signalement avant de centrer la carte.',
            ),
          ),
        );
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final positionEstimateService = widget.positionEstimateService;

    final map = MapScreen(
      focusController: _mapFocusController,
      onOpenAlerts:
          widget.alertService == null || widget.reportDetailService == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AlertsScreen(
                    service: widget.alertService!,
                    onOpen: (alert) => _openReport(alert.reportId),
                  ),
                ),
              );
            },
      reportService: widget.reportService,
      reportTiles: widget.reportTiles,
      reportDetailService: widget.reportDetailService,
      onUserInactive: widget.onUserInactive,
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
              Navigator.of(context).push(
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
              );
            },
    );

    final controller = widget.pushController;
    return controller == null
        ? map
        : PushNotificationListener(
            controller: controller,
            onOpen: (push) => _openReportFromPush(push.alert.reportId),
            child: map,
          );
  }
}
