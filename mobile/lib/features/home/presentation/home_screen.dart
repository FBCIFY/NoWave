import 'package:flutter/material.dart';

import '../../map/data/report_tiles.dart';
import '../../map/presentation/map_screen.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../reports/data/manual_report_service.dart';
import '../../reports/data/report_detail_service.dart';
import '../../camera/data/position_estimate_service.dart';
import '../../camera/domain/photo_report_draft.dart';
import '../../camera/presentation/camera_screen.dart';
import '../../../core/notifications/notification_permission.dart';

/// Accueil après connexion : la carte, avec un bouton qui ouvre le profil.
class HomeScreen extends StatelessWidget {
  final UserProfile? profile;
  final Future<void> Function()? onSignOut;
  final UpdatePreferences? onUpdatePreferences;
  final ManualReportService? reportService;
  final PositionEstimateService? positionEstimateService;
  final ReportTiles? reportTiles;
  final ReportDetailService? reportDetailService;

  const HomeScreen({
    super.key,
    this.profile,
    this.onSignOut,
    this.onUpdatePreferences,
    this.reportService,
    this.positionEstimateService,
    this.reportTiles,
    this.reportDetailService,
  });

  @override
  Widget build(BuildContext context) {
    final positionEstimateService = this.positionEstimateService;

    return MapScreen(
      reportService: reportService,
      reportTiles: reportTiles,
      reportDetailService: reportDetailService,
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
  }
}
