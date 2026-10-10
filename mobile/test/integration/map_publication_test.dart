import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:blueway/features/camera/domain/photo_report_draft.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/presentation/report_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Gps extends geo.GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<geo.LocationPermission> checkPermission() async =>
      geo.LocationPermission.whileInUse;
  @override
  Future<geo.Position> getCurrentPosition({
    geo.LocationSettings? locationSettings,
  }) async => geo.Position(
    longitude: 5.37,
    latitude: 43.29,
    timestamp: DateTime.utc(2026, 10, 10),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );
}

class _Compass extends Fake implements CompassSettingsInterface {
  @override
  Future<void> updateSettings(CompassSettings settings) async {}
}

class _Scale extends Fake implements ScaleBarSettingsInterface {
  @override
  Future<void> updateSettings(ScaleBarSettings settings) async {}
}

class _Map extends Fake implements MapboxMap {
  @override
  final compass = _Compass();
  @override
  final scaleBar = _Scale();
  @override
  Future<CameraState> getCameraState() async => CameraState(
    center: Point(coordinates: Position(5.37, 43.29)),
    zoom: 14,
    pitch: 0,
    bearing: 0,
    padding: MbxEdgeInsets(top: 0, left: 0, right: 0, bottom: 0),
  );
  @override
  Future<Point> coordinateForPixel(ScreenCoordinate pixel) async =>
      Point(coordinates: Position(5.37, 43.29));
  @override
  Future<void> easeTo(
    CameraOptions options,
    MapAnimationOptions? animationOptions,
  ) async {}
}

void main() {
  late geo.GeolocatorPlatform previousGps;
  setUp(() {
    previousGps = geo.GeolocatorPlatform.instance;
    geo.GeolocatorPlatform.instance = _Gps();
  });
  tearDown(() => geo.GeolocatorPlatform.instance = previousGps);

  Future<void> mount(
    WidgetTester tester,
    MockClient client, {
    bool photo = false,
  }) async {
    addTearDown(client.close);
    final capture = PhotoCapture(
      jpegBytes: img.encodeJpg(img.Image(width: 4, height: 4)),
      measurements: PhotoCaptureMeasurements(
        observerLongitude: 5.37,
        observerLatitude: 43.29,
        gpsAccuracyMeters: 5,
        azimuthDegrees: 0,
        inclinationDegrees: -10,
        cameraHeightMeters: 2,
        cameraHeightSource: 'default',
        cameraHeightUncertaintyMeters: 0.5,
        capturedAt: DateTime.utc(2026, 10, 10),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          reportService: ManualReportService(
            apiService: ApiService(
              client: client,
              baseUrl: 'https://nowave.test/',
            ),
            getIdToken: () async => 'test-token',
          ),
          onOpenCamera: photo
              ? () async => PhotoReportDraft(capture: capture, estimate: null)
              : null,
        ),
      ),
    );
    tester.widget<MapWidget>(find.byType(MapWidget)).onMapCreated!(_Map());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip(
        photo ? 'Signaler avec une photo' : 'Créer un signalement',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReportComposerSheet), findsOneWidget);
    await tester.tap(find.text('Pollution'));
    await tester.pump();
  }

  testWidgets(
    'NW128-I06 réponse POST perdue : même clé et une création serveur simulée',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final stored = <String, String>{};
      final client = MockClient((r) async {
        expect(r.url.path, '/api/v1/reports');
        expect(r.headers['authorization'], 'Bearer test-token');
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        requests.add(body);
        final id = stored.putIfAbsent(
          body['client_report_id'] as String,
          () => 'report-${stored.length}',
        );
        if (requests.length == 1) {
          throw TimeoutException('réponse perdue après commit simulé');
        }
        return http.Response(jsonEncode({'id': id}), 201);
      });
      await mount(tester, client);
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportComposerSheet), findsOneWidget);
      expect(requests, hasLength(1));
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests[1], requests[0]);
      expect(stored, hasLength(1));
      expect(find.byType(ReportComposerSheet), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'NW128-I07 publication puis upload échoué : retry sans republication et fermeture réelle',
    (tester) async {
      var creates = 0;
      var uploads = 0;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/photo')) {
          uploads++;
          expect(r.url.path, '/api/v1/reports/photo-report/photo');
          return http.Response('', 503);
        }
        creates++;
        expect((jsonDecode(r.body) as Map)['positioning_mode'], 'photo');
        return http.Response('{"id":"photo-report"}', 201);
      });
      await mount(tester, client, photo: true);
      await tester.tap(find.text('Publier le signalement'));
      await tester.pumpAndSettle();
      expect(find.text('Signalement publié'), findsOneWidget);
      expect(find.text('Photo non envoyée. Réessayez.'), findsOneWidget);
      await tester.tap(find.text('Réessayer l’envoi'));
      await tester.pumpAndSettle();
      expect(creates, 1);
      expect(uploads, 2);
      await tester.tap(find.text('Terminer sans photo'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportComposerSheet), findsNothing);
      expect(find.text('Signalement publié sans photo.'), findsOneWidget);
      expect(find.byTooltip('Créer un signalement'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
