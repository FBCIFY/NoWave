import 'package:flutter/material.dart';

import '../../map/presentation/map_screen.dart';
import '../../reports/data/report_detail_service.dart';
import '../../reports/domain/report_detail.dart';
import '../../reports/presentation/report_detail_sheet.dart';

/// Même fiche que sur la carte ; seules les données relues auprès de l'API
/// permettent d'ouvrir la carte, jamais la position historique du push.
class AlertReportScreen extends StatelessWidget {
  const AlertReportScreen({
    super.key,
    required this.reportId,
    required this.service,
    this.now = DateTime.now,
    this.onShowOnMap,
  });
  final String reportId;
  final ReportDetailService service;
  final DateTime Function() now;
  final Future<void> Function(ReportDetail)? onShowOnMap;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Signalement de l’alerte')),
    body: ReportDetailSheet(
      reportId: reportId,
      loadReport: (id) async {
        final report = await service.fetchReport(id);
        if (!report.expiresAt.isAfter(now())) {
          throw const ReportNotFoundException();
        }
        return report;
      },
      loadPhoto: service.fetchPhoto,
      now: now,
      onShowOnMap: (report) async {
        final ReportDetail current;
        try {
          current = await service.fetchReport(report.id);
          if (!current.expiresAt.isAfter(now())) {
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
        if (!current.expiresAt.isAfter(now())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ce signalement a expiré.')),
          );
          return;
        }
        final callback = onShowOnMap;
        if (callback != null) {
          await callback(current);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                MapScreen(initialReport: current, reportDetailService: service),
          ),
        );
      },
    ),
  );
}
