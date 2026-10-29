import 'dart:convert';
import 'dart:typed_data';

import 'package:blueway/core/api/api_exception.dart';
import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('envoie le signalement manuel authentifié au contrat backend', () async {
    final request = ManualReportRequest(
      clientReportId: '550e8400-e29b-41d4-a716-446655440000',
      category: ReportCategory.pollution,
      longitude: 5.123456,
      latitude: 43.123456,
      observedAt: DateTime.utc(2026, 9, 23, 13, 45),
      description: 'Pollution visible',
    );
    final client = MockClient((httpRequest) async {
      expect(httpRequest.method, 'POST');
      expect(
        httpRequest.url,
        Uri.parse('https://api.blueway.test/api/v1/reports'),
      );
      expect(httpRequest.headers['authorization'], 'Bearer firebase-token');
      expect(httpRequest.headers['content-type'], 'application/json');
      expect(jsonDecode(httpRequest.body), {
        'client_report_id': request.clientReportId,
        'category': 'pollution',
        'description': 'Pollution visible',
        'final_position': {
          'type': 'Point',
          'coordinates': [5.123456, 43.123456],
        },
        'observed_at': '2026-09-23T13:45:00.000Z',
      });
      return http.Response(jsonEncode({'id': 'report-id'}), 201);
    });
    final service = ManualReportService(
      apiService: ApiService(
        client: client,
        baseUrl: 'https://api.blueway.test/',
      ),
      getIdToken: () async => 'firebase-token',
    );

    expect(await service.createReport(request), 'report-id');
    expect(
      request.matchesContent(
        category: ReportCategory.pollution,
        longitude: 5.123456,
        latitude: 43.123456,
        description: 'Pollution visible',
      ),
      isTrue,
    );
    expect(
      request.matchesContent(
        category: ReportCategory.obstruction,
        longitude: 5.123456,
        latitude: 43.123456,
        description: 'Pollution visible',
      ),
      isFalse,
    );
  });

  group('uploadPhoto', () {
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

    ManualReportService serviceFor(MockClient client) => ManualReportService(
      apiService: ApiService(
        client: client,
        baseUrl: 'https://api.blueway.test/',
      ),
      getIdToken: () async => 'firebase-token',
    );

    test('envoie le JPEG en multipart dans le champ file', () async {
      final client = MockClient((httpRequest) async {
        expect(httpRequest.method, 'POST');
        expect(
          httpRequest.url,
          Uri.parse('https://api.blueway.test/api/v1/reports/report-id/photo'),
        );
        expect(httpRequest.headers['authorization'], 'Bearer firebase-token');
        expect(
          httpRequest.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        final body = latin1.decode(httpRequest.bodyBytes);
        expect(body, contains('name="file"; filename="photo.jpg"'));
        expect(body, contains('content-type: image/jpeg'));
        expect(body, contains(latin1.decode(jpegBytes)));
        return http.Response(
          jsonEncode({
            'report_id': 'report-id',
            'upload_status': 'uploaded',
            'size_bytes': jpegBytes.length,
            'mime_type': 'image/jpeg',
          }),
          201,
        );
      });

      await serviceFor(client)
          .uploadPhoto(reportId: 'report-id', jpegBytes: jpegBytes);
    });

    test('refuse une réponse qui ne confirme pas l’envoi', () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode({'upload_status': 'pending'}), 201),
      );

      await expectLater(
        serviceFor(client)
            .uploadPhoto(reportId: 'report-id', jpegBytes: jpegBytes),
        throwsFormatException,
      );
    });

    test('remonte le 404 du backend en ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'Not Found'}), 404),
      );

      await expectLater(
        serviceFor(client)
            .uploadPhoto(reportId: 'report-id', jpegBytes: jpegBytes),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });
  });
}
