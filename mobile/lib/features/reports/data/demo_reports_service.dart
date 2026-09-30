import 'reports_service.dart';

/// Données fictives pour `ReportsScreen`.
class DemoReportsService implements ReportsService {
  @override
  Future<List<String>> fetchReports() async {
    await Future<void>.delayed(const Duration(seconds: 1));

    return ['Obstacle signalé près du port', 'Pollution observée au large'];
  }
}
