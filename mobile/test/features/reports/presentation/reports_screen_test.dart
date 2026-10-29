import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/reports/data/reports_service.dart';
import 'package:blueway/features/reports/presentation/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _HttpReportsService implements ReportsService {
  _HttpReportsService(this._apiService);

  final ApiService _apiService;

  @override
  Future<List<String>> fetchReports() async {
    await _apiService.get('reports');

    return [];
  }
}

void main() {
  testWidgets('affiche une erreur quand la requête HTTP échoue', (
    tester,
  ) async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://example.com/reports'));

      return http.Response('Erreur serveur', 500);
    });

    addTearDown(client.close);

    final service = _HttpReportsService(
      ApiService(client: client, baseUrl: 'https://example.com/'),
    );

    await tester.pumpWidget(MaterialApp(home: ReportsScreen(service: service)));

    expect(find.text('Chargement…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger les signalements'), findsOneWidget);
  });
}
