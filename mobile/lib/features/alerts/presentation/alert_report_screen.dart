import 'package:flutter/material.dart';

import '../../../core/location/location_service.dart';

import '../../reports/data/report_detail_service.dart';
import '../../reports/domain/report_detail.dart';
import '../../reports/presentation/report_detail_sheet.dart';

/// Même fiche que sur la carte ; seules les données relues auprès de l'API
/// permettent d'ouvrir la carte, jamais la position historique du push.
class AlertReportScreen extends StatefulWidget {
  const AlertReportScreen({
    super.key,
    required this.reportId,
    required this.service,
    this.now = DateTime.now,
    this.locationService,
    required this.onShowOnMap,
  });
  final String reportId;
  final ReportDetailService service;
  final DateTime Function() now;
  final Future<void> Function(ReportDetail) onShowOnMap;

  final LocationService? locationService;

  @override
  State<AlertReportScreen> createState() => _AlertReportScreenState();
}

class _AlertReportScreenState extends State<AlertReportScreen> {
  ({double latitude, double longitude})? _userPosition;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final location = widget.locationService ?? LocationService();
    try {
      // La consultation d'une alerte ne demande pas une nouvelle permission.
      if (!await location.canWatchPosition()) return;
      final position = await location.getCurrentPosition();
      if (!mounted ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        return;
      }
      setState(
        () => _userPosition = (
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } catch (_) {
      // La fiche reste consultable sans GPS.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Signalement de l’alerte')),
    body: ReportDetailSheet(
      reportId: widget.reportId,
      userPosition: _userPosition,
      loadReport: (id) async {
        final report = await widget.service.fetchReport(id);
        if (!report.expiresAt.isAfter(widget.now())) {
          throw const ReportNotFoundException();
        }
        return report;
      },
      loadPhoto: widget.service.fetchPhoto,
      now: widget.now,
      onShowOnMap: (report) async {
        final ReportDetail current;
        try {
          current = await widget.service.fetchReport(report.id);
          if (!current.expiresAt.isAfter(widget.now())) {
            throw const ReportNotFoundException();
          }
        } on ReportNotFoundException {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ce signalement n’est plus disponible.'),
              ),
            );
          }
          return;
        }
        if (!context.mounted) return;
        await widget.onShowOnMap(current);
      },
    ),
  );
}
