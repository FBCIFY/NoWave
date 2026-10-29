import 'package:flutter/material.dart';

import '../data/demo_reports_service.dart';
import '../data/reports_service.dart';

/// Liste de démonstration, non accessible depuis l'app (utilisée seulement
/// dans les tests).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.service});

  final ReportsService? service;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final Future<List<String>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = (widget.service ?? DemoReportsService()).fetchReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signalements')),
      body: FutureBuilder<List<String>>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: Text('Chargement…'));
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Impossible de charger les signalements'),
            );
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const Center(child: Text('Aucun signalement'));
          }

          return ListView(
            children: [
              for (final report in reports) ListTile(title: Text(report)),
            ],
          );
        },
      ),
    );
  }
}
