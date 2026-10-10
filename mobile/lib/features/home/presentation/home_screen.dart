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
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';

/// Accueil après connexion : la carte, avec un bouton qui ouvre le profil.
class HomeScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final positionEstimateService = this.positionEstimateService;

    Future<void> openReport(String reportId) async {
      final service = reportDetailService;
      if (service == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AlertReportScreen(reportId: reportId, service: service),
        ),
      );
    }

    final map = MapScreen(
      onOpenAlerts: alertService == null || reportDetailService == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AlertsScreen(
                    service: alertService!,
                    onOpen: (alert) => openReport(alert.reportId),
                  ),
                ),
              );
            },
      reportService: reportService,
      reportTiles: reportTiles,
      reportDetailService: reportDetailService,
      onUserInactive: onUserInactive,
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
          profile == null || onSignOut == null || onUpdatePreferences == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileScreen(
                    profile: profile!,
                    onSignOut: onSignOut!,
                    onUpdatePreferences: onUpdatePreferences!,
                    notificationPermissions:
                        const NotificationPermissionService(),
                  ),
                ),
              );
            },
    );
    final controller = pushController;
    return controller == null
        ? map
        : PushNotificationListener(
            controller: controller,
            onOpen: (push) => openReport(push.alert.reportId),
            child: map,
          );
  }
}
