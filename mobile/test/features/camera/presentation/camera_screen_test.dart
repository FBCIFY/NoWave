import 'dart:async';

import 'dart:convert';

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/sensors/camera_inclination_service.dart';
import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/camera/data/position_estimate_service.dart';
import 'package:blueway/features/camera/domain/photo_report_draft.dart';
import 'package:blueway/features/camera/presentation/camera_screen.dart';
import 'package:blueway/features/camera/presentation/report_camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:precise_compass/precise_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/haptics/record_haptics.dart';

void main() {
  testWidgets('« Reprendre » efface la photo et rend le déclencheur', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    final camera = _FakeCamera();
    await _openCameraScreen(tester, camera: camera);

    expect(find.text('±8 m · cap 245° · inclinaison -10°'), findsOneWidget);
    expect(find.byKey(_previewKey), findsOneWidget);

    await _takePhoto(tester);
    expect(camera.pictures, 1);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    // La photo figée remplace l'aperçu, avec les mesures prises à l'appui.
    expect(find.byKey(_previewKey), findsNothing);
    expect(
      find.textContaining('Photo prise (').evaluate().single.widget,
      isA<Text>().having(
        (text) => text.data,
        'data',
        endsWith('±8 m · cap 245° · inclinaison -10°'),
      ),
    );
    expect(find.bySemanticsLabel('Prendre la photo'), findsNothing);

    await tester.tap(find.text('Reprendre'));
    await tester.pump();
    expect(find.byKey(_previewKey), findsOneWidget);
    expect(find.bySemanticsLabel('Prendre la photo'), findsOneWidget);
    expect(find.text('Reprendre'), findsNothing);
    expect(find.textContaining('Photo prise ('), findsNothing);

    await _takePhoto(tester);
    expect(camera.pictures, 2);
  });

  testWidgets('« Continuer » renvoie la photo et l’estimation à la carte', (
    tester,
  ) async {
    final camera = _FakeCamera();
    final requests = <Map<String, dynamic>>[];
    final result = await _openCameraScreen(
      tester,
      camera: camera,
      estimate: (request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'estimated_position': {
              'type': 'Point',
              'coordinates': [-4.4862, 48.3903],
            },
            'estimated_distance_m': 11,
          }),
          200,
        );
      },
    );

    await _takePhoto(tester);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(find.byType(CameraScreen), findsNothing);
    expect(camera.isDisposed, isTrue);

    final draft = await result;
    expect(draft, isNotNull);
    expect(draft!.estimate!.distanceMeters, 11);
    expect(draft.capture.jpegBytes, isNotEmpty);
    final measurements = draft.capture.measurements;
    expect(measurements.observerLongitude, -4.4861);
    expect(measurements.observerLatitude, 48.3904);
    expect(measurements.gpsAccuracyMeters, 8);
    expect(measurements.azimuthDegrees, 245);
    expect(measurements.inclinationDegrees, closeTo(-10, 0.1));
  });

  testWidgets('bloque « Reprendre » et « Continuer » pendant l’estimation', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    await _openCameraScreen(tester, estimate: (_) => response.future);

    await _takePhoto(tester);
    await tester.tap(find.text('Continuer'));
    await tester.pump();

    expect(find.text('Continuer'), findsNothing);
    expect(_button('Reprendre').onPressed, isNull);

    // Un second appui sur « Reprendre » ne doit pas effacer la photo envoyée.
    await tester.tap(find.text('Reprendre'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Reprendre'), findsOneWidget);

    response.complete(http.Response('', 503));
    await tester.pump();
    expect(find.text('Estimation impossible. Réessayez.'), findsOneWidget);
    expect(_button('Reprendre').onPressed, isNotNull);
    expect(_button('Continuer').onPressed, isNotNull);
  });

  group('affiche l’erreur d’estimation', () {
    final cases = <String, (http.Response, String)>{
      '422 précision GPS': (
        _error(422, 'gps_precision_insufficient'),
        'Précision GPS insuffisante. Reprenez la photo.',
      ),
      '422 autre code': (
        _error(422, 'request_validation_error'),
        'Mesures refusées. Reprenez la photo.',
      ),
      '401': (
        _error(401, 'unauthorized'),
        'Votre session a expiré. Reconnectez-vous.',
      ),
      '403': (
        _error(403, 'forbidden'),
        'Votre compte ne peut pas publier de signalement.',
      ),
      '404': (
        http.Response('Not Found', 404),
        'Estimation indisponible sur ce serveur.',
      ),
      '503': (http.Response('', 503), 'Estimation impossible. Réessayez.'),
    };

    for (final MapEntry(key: name, value: (response, message))
        in cases.entries) {
      testWidgets(name, (tester) async {
        await _openCameraScreen(tester, estimate: (_) async => response);

        await _takePhoto(tester);
        await tester.tap(find.text('Continuer'));
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        // L'écran reste ouvert sur la photo : on peut réessayer ou reprendre.
        expect(find.byType(CameraScreen), findsOneWidget);
        expect(find.text('Continuer'), findsOneWidget);
        expect(find.text('Reprendre'), findsOneWidget);
      });
    }

    testWidgets('réseau', (tester) async {
      await _openCameraScreen(
        tester,
        estimate: (_) async => throw http.ClientException('hors ligne'),
      );

      await _takePhoto(tester);
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      const message = 'Estimation impossible. Vérifiez votre connexion.';
      expect(find.text(message), findsOneWidget);

      // Reprendre la photo efface l'erreur.
      await tester.tap(find.text('Reprendre'));
      await tester.pump();
      expect(find.text(message), findsNothing);
    });
  });
}

const _previewKey = ValueKey('camera-preview');

/// Ouvre l'écran comme la carte, pour récupérer ce qu'il renvoie en se
/// fermant.
Future<Future<PhotoReportDraft?>> _openCameraScreen(
  WidgetTester tester, {
  _FakeCamera? camera,
  MockClientHandler? estimate,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: Scaffold()));

  final result = tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(
        MaterialPageRoute<PhotoReportDraft>(
          builder: (_) => CameraScreen(
            positionEstimateService: PositionEstimateService(
              apiService: ApiService(
                client: MockClient(
                  estimate ?? (_) async => http.Response('', 503),
                ),
                baseUrl: 'https://api.blueway.test/',
              ),
              getIdToken: () async => 'firebase-token',
            ),
            camera: camera ?? _FakeCamera(),
            locationService: _FakeLocationService(),
            orientationService: _FakeOrientationService(),
            inclinationService: CameraInclinationService(
              // Gravité d'un téléphone qui vise 10° sous l'horizon.
              accelerometer: Stream.value(
                AccelerometerEvent(
                  0,
                  9.81 * 0.9848,
                  9.81 * 0.1736,
                  DateTime(2026),
                ),
              ),
            ),
          ),
        ),
      );
  await tester.pumpAndSettle();

  return result;
}

/// Le JPEG est préparé par compute(), dans un vrai isolate : on laisse passer
/// du temps réel jusqu'à ce que la photo s'affiche.
Future<void> _takePhoto(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Prendre la photo'));

  for (var i = 0; i < 200 && find.text('Reprendre').evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }

  expect(find.text('Reprendre'), findsOneWidget);
}

ButtonStyleButton _button(String label) {
  return find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .evaluate()
          .first
          .widget
      as ButtonStyleButton;
}

http.Response _error(int statusCode, String code) {
  return http.Response(
    jsonEncode({
      'error': {'code': code, 'message': 'Erreur', 'details': null},
    }),
    statusCode,
  );
}

class _FakeCamera implements ReportCamera {
  int pictures = 0;
  bool isDisposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() =>
      const ColoredBox(key: _previewKey, color: Colors.blueGrey);

  @override
  Future<Uint8List> takePicture() async {
    pictures++;
    return img.encodeJpg(img.Image(width: 64, height: 48));
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

class _FakeLocationService extends LocationService {
  @override
  Future<geo.Position> getCurrentPosition() async => geo.Position(
    longitude: -4.4861,
    latitude: 48.3904,
    timestamp: DateTime(2026),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Stream<geo.Position> watchPosition() => const Stream.empty();
}

class _FakeOrientationService extends DeviceOrientationService {
  @override
  Stream<CompassReading> get readings => Stream.value(
    CompassReading.unavailable(timestamp: DateTime(2026))
        .copyWith(headingTrue: 245, heading: 245),
  );
}
