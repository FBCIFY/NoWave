import 'dart:async';
import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/map/map_controller.dart';
import 'package:blueway/core/map/map_view.dart';
import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:blueway/features/camera/domain/photo_report_draft.dart';
import 'package:blueway/features/camera/domain/position_estimate.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/presentation/widgets/report_marker.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';
import 'package:blueway/features/reports/presentation/report_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:precise_compass/precise_compass.dart';

import '../../../core/haptics/record_haptics.dart';

void main() {
  testWidgets('création, GPS initial, suivi continu et flèche projetée', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    expect(h.map.camera.target, const LatLng(43.2, 5.4));
    expect(h.map.camera.zoom, 14);
    expect(find.textContaining('Lat.'), findsOneWidget);
    expect(find.byIcon(Icons.navigation), findsNWidgets(2));
    h.gps.positions.add(_position(43.3, 5.5));
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.3, 5.5));
    expect(h.map.projected, contains(const LatLng(43.3, 5.5)));
    await h.close(tester);
  });
  testWidgets('geste coupe le suivi ; recentrage retrouve zoom 14 et le GPS', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    await tester.drag(find.byKey(_mapKey), const Offset(30, 0));
    await tester.pump();
    final count = h.map.moves.length;
    h.gps.positions.add(_position(43.4, 5.6));
    await tester.pump();
    expect(h.map.moves.length, count);
    await tester.tap(find.byTooltip('Recentrer sur ma position'));
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.2, 5.4));
    expect(h.map.camera.zoom, 14);
    expect(h.map.lastDuration, const Duration(milliseconds: 1200));
    h.gps.positions.add(_position(43.5, 5.7));
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.5, 5.7));
    await h.close(tester);
  });
  testWidgets('heading-up suit les lectures ; north-up fixe le nord', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    h.heading(90);
    await tester.pump();
    await tester.tap(find.byTooltip('Aligner la carte sur le cap actuel'));
    await tester.pump();
    expect(h.map.camera.bearing, 90);
    h.heading(120);
    await tester.pump();
    expect(h.map.camera.bearing, 120);
    await tester.tap(find.byTooltip('Orienter la carte vers le nord'));
    await tester.pump();
    h.heading(180);
    await tester.pump();
    expect(h.map.camera.bearing, 0);
    await h.close(tester);
  });
  testWidgets('rotation manuelle conserve le cap choisi après recentrage', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_mapKey)),
    );
    h.map.emit(
      const CameraPosition(target: LatLng(43.2, 5.4), zoom: 8, bearing: 47),
    );
    await gesture.up();
    await tester.pump();
    h.heading(180);
    await tester.pump();
    expect(h.map.camera.bearing, 47);
    await tester.tap(find.byTooltip('Recentrer sur ma position'));
    await tester.pump();
    expect(h.map.camera.bearing, 47);
    expect(h.map.camera.zoom, 14);
    await h.close(tester);
  });
  testWidgets('GPS refusé : message puis récupération par recentrage', (
    tester,
  ) async {
    final h = await _Harness.open(tester, denied: true);
    expect(find.text('Accès GPS refusé.'), findsOneWidget);
    h.gps.denied = false;
    await tester.tap(find.byTooltip('Recentrer sur ma position'));
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.2, 5.4));
    expect(find.text('Accès GPS refusé.'), findsNothing);
    await h.close(tester);
  });
  testWidgets('carte indisponible : erreur et recréation au réessai', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    h.options.onError('Serveur cartographique indisponible.');
    await tester.pump();
    expect(find.text('Serveur cartographique indisponible.'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(h.options.generation, 1);
    expect(find.text('Serveur cartographique indisponible.'), findsNothing);
    h.options.onReady(h.map);
    await tester.pump();
    expect(h.map.camera.zoom, 14);
    await h.close(tester);
  });
  testWidgets(
    'manuel : pointe fixe, marqueur relevé, coordonnées fraîches et publication',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/reports');
        expect(request.headers['Authorization'], 'Bearer firebase-test');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"id":"report-1"}', 201);
      });
      final h = await _Harness.open(tester, client: client);
      await h.openComposer(tester);
      expect(h.options.editing, isTrue);
      expect(h.map.camera.tilt, 0);
      expect(h.map.padding.bottom, greaterThan(0));
      final markerTip =
          tester.getTopLeft(find.byType(ReportMarker)) + const Offset(22, 40);
      await tester.pump(const Duration(milliseconds: 61));
      expect(h.map.lastPixel, markerTip);
      h.map.pointAtPixel = const LatLng(43.2222224, 5.5555554);
      h.map.emit(h.map.camera);
      await tester.pump();
      expect(
        tester.widget<ReportMarker>(find.byType(ReportMarker)).lifted,
        isTrue,
      );
      expect(
        tester.getTopLeft(find.byType(ReportMarker)) + const Offset(22, 40),
        markerTip,
      );
      await tester.pump(const Duration(milliseconds: 210));
      expect(
        tester.widget<ReportMarker>(find.byType(ReportMarker)).lifted,
        isFalse,
      );
      await tester.tap(find.text('Pollution'));
      await tester.pump();
      await tester.tap(find.text('Publier le signalement'));
      await tester.pump();
      await tester.pump();
      expect(requests.single['final_position']['coordinates'], [
        5.555555,
        43.222222,
      ]);
      expect(find.byType(ReportComposerSheet), findsNothing);
      expect(find.text('Signalement publié.'), findsOneWidget);
      expect(h.map.padding, EdgeInsets.zero);
      await h.close(tester);
    },
  );
  testWidgets('échec publication : retry conserve client_report_id', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return requests.length == 1
          ? http.Response('indisponible', 503)
          : http.Response('{"id":"r"}', 201);
    });
    final h = await _Harness.open(tester, client: client);
    await h.openComposer(tester);
    await tester.tap(find.text('Obstacle'));
    await tester.pump();
    await tester.tap(find.text('Publier le signalement'));
    await tester.pump();
    expect(find.byType(ReportComposerSheet), findsOneWidget);
    await tester.tap(find.text('Publier le signalement'));
    await tester.pump();
    await tester.pump();
    expect(requests.length, 2);
    expect(requests[0]['client_report_id'], requests[1]['client_report_id']);
    await h.close(tester);
  });
  testWidgets(
    'photo : estimation, correction, publication puis retry JPEG sans doublon',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      var uploads = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/photo')) {
          uploads++;
          expect(request.url.path, '/api/v1/reports/photo-report/photo');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data'),
          );
          return uploads == 1
              ? http.Response('indisponible', 503)
              : http.Response('{"upload_status":"uploaded"}', 200);
        }
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"id":"photo-report"}', 201);
      });
      final draft = _photo();
      final h = await _Harness.open(tester, client: client, photo: draft);
      await tester.tap(find.byTooltip('Signaler avec une photo'));
      await tester.pump();
      await tester.pump();
      expect(h.map.camera.target, const LatLng(43.21, 5.41));
      expect(h.map.camera.zoom, 16);
      expect(find.text('Estimé à 150 m · ajustez si besoin'), findsOneWidget);
      h.map.pointAtPixel = const LatLng(43.22, 5.42);
      h.gps.positions.add(_position(44, 6));
      await tester.pump();
      expect(h.map.camera.target, const LatLng(43.21, 5.41));
      await tester.tap(find.text('Animal marin'));
      await tester.pump();
      await tester.tap(find.text('Publier le signalement'));
      await tester.pump();
      expect(requests.single['final_position']['coordinates'], [5.42, 43.22]);
      expect(
        requests.single['positioning'],
        draft.capture.measurements.toJson(),
      );
      expect(uploads, 1);
      await tester.tap(find.text('Réessayer l’envoi'));
      await tester.pump();
      await tester.pump();
      expect(uploads, 2);
      expect(requests.length, 1);
      expect(find.byType(ReportComposerSheet), findsNothing);
      expect(find.text('Signalement publié avec sa photo.'), findsOneWidget);
      expect(h.map.camera.target, const LatLng(44, 6));
      await h.close(tester);
    },
  );
  testWidgets('photo sans estimation part du GPS figé même sans GPS actuel', (
    tester,
  ) async {
    final photo = _photo();
    final h = await _Harness.open(
      tester,
      denied: true,
      photo: PhotoReportDraft(capture: photo.capture, estimate: null),
    );
    await tester.tap(find.byTooltip('Signaler avec une photo'));
    await tester.pump();
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.19, 5.39));
    expect(
      find.text('Placez le point sur l’objet photographié'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await h.close(tester);
  });
  testWidgets('fermeture demande confirmation et rétablit la caméra/suivi', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    await h.openComposer(tester);
    await tester.enterText(find.byType(TextField), 'Objet à vérifier');
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Abandonner ce signalement ?'), findsOneWidget);
    await tester.tap(find.text('Abandonner'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportComposerSheet), findsNothing);
    expect(h.map.camera.tilt, 60);
    h.gps.positions.add(_position(43.6, 5.8));
    await tester.pump();
    expect(h.map.camera.target, const LatLng(43.6, 5.8));
    await h.close(tester);
  });
}

const _mapKey = ValueKey('fake-map-surface');

class _Harness {
  final gps = _Gps();
  final headings = StreamController<CompassReading>.broadcast(sync: true);
  final map = _Map();
  late MapViewOptions options;
  http.Client? client;
  static Future<_Harness> open(
    WidgetTester tester, {
    http.Client? client,
    PhotoReportDraft? photo,
    bool denied = false,
  }) async {
    recordHaptics(tester);
    final h = _Harness()..client = client;
    h.gps.denied = denied;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          locationService: h.gps,
          headingReadings: h.headings.stream,
          onOpenCamera: photo == null ? null : () async => photo,
          reportService: client == null
              ? null
              : ManualReportService(
                  apiService: ApiService(
                    client: client,
                    baseUrl: 'https://backend.example/',
                  ),
                  getIdToken: () async => 'firebase-test',
                ),
          mapViewBuilder: (options) {
            h.options = options;
            h.map.options = options;
            return const ColoredBox(
              key: _mapKey,
              color: Colors.white,
              child: SizedBox.expand(),
            );
          },
        ),
      ),
    );
    h.options.onReady(h.map);
    await tester.pump();
    await tester.pump();
    return h;
  }

  void heading(double heading) => headings.add(
    CompassReading.unavailable(timestamp: DateTime(2026))
        .copyWith(headingTrue: heading, heading: heading),
  );
  Future<void> openComposer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Créer un signalement'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await headings.close();
    await gps.positions.close();
    client?.close();
  }
}

class _Map implements NoWaveMapController {
  late MapViewOptions options;
  @override
  CameraPosition camera = const CameraPosition(
    target: LatLng(43.15, 5.35),
    zoom: 7,
    tilt: 60,
  );
  final moves = <CameraPosition>[];
  final projected = <LatLng>[];
  Duration? lastDuration;
  EdgeInsets padding = EdgeInsets.zero;
  Offset? lastPixel;
  LatLng pointAtPixel = const LatLng(43.2, 5.4);
  void emit(CameraPosition position) {
    camera = position;
    options.onCameraMove(position);
  }

  @override
  Future<void> move(CameraPosition position, {Duration? duration}) async {
    lastDuration = duration;
    moves.add(position);
    emit(position);
  }

  @override
  Future<void> setPadding(EdgeInsets value) async {
    padding = value;
  }

  @override
  Future<LatLng> coordinateForPixel(Offset pixel) async {
    lastPixel = pixel;
    return pointAtPixel;
  }

  @override
  Future<Offset> pixelForCoordinate(LatLng coordinate) async {
    projected.add(coordinate);
    return const Offset(120, 140);
  }
}

class _Gps extends LocationService {
  final positions = StreamController<geo.Position>.broadcast(sync: true);
  bool denied = false;
  @override
  Future<geo.Position> getCurrentPosition() async {
    if (denied) throw StateError('Accès GPS refusé.');
    return _position(43.2, 5.4);
  }

  @override
  Stream<geo.Position> watchPosition() => positions.stream;
}

geo.Position _position(double latitude, double longitude) => geo.Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
PhotoReportDraft _photo() => PhotoReportDraft(
  capture: PhotoCapture(
    jpegBytes: img.encodeJpg(img.Image(width: 4, height: 4)),
    measurements: PhotoCaptureMeasurements(
      observerLongitude: 5.39,
      observerLatitude: 43.19,
      gpsAccuracyMeters: 8,
      azimuthDegrees: 90,
      inclinationDegrees: -10,
      cameraHeightMeters: 2.5,
      cameraHeightSource: 'default',
      cameraHeightUncertaintyMeters: 1,
      capturedAt: DateTime.utc(2026, 10, 4),
    ),
  ),
  estimate: const PositionEstimate(
    longitude: 5.41,
    latitude: 43.21,
    distanceMeters: 150,
  ),
);
