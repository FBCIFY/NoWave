import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:blueway/core/api/api_service.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/sensors/camera_axis_service.dart';
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
    expect(requests.single['focal_length_mm'], closeTo(4.25, 1e-9));
    expect(requests.single['zoom_ratio'], 1);
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
    expect(measurements.azimuthDegrees, closeTo(245, 1e-6));
    expect(measurements.inclinationDegrees, closeTo(-10, 0.1));
    expect(measurements.focalLengthMm, closeTo(4.25, 1e-9));
    expect(measurements.zoomRatio, 1);
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
    // Réponse, message, et si le point manuel est proposé (panne seulement).
    final cases = <String, (http.Response, String, bool)>{
      '422 précision GPS': (
        _error(422, 'gps_precision_insufficient'),
        'Précision GPS insuffisante. Reprenez la photo.',
        false,
      ),
      '422 autre code': (
        _error(422, 'request_validation_error'),
        'Mesures refusées. Reprenez la photo.',
        false,
      ),
      '401': (
        _error(401, 'unauthorized'),
        'Votre session a expiré. Reconnectez-vous.',
        false,
      ),
      '403': (
        _error(403, 'forbidden'),
        'Votre compte ne peut pas publier de signalement.',
        false,
      ),
      '404': (
        http.Response('Not Found', 404),
        'Estimation indisponible sur ce serveur.',
        true,
      ),
      '429': (
        _error(429, 'rate_limited'),
        'Estimation impossible. Réessayez.',
        true,
      ),
      '503': (
        http.Response('', 503),
        'Estimation impossible. Réessayez.',
        true,
      ),
    };

    for (final MapEntry(key: name, value: (response, message, manual))
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
        expect(
          find.text('Placer le point moi-même'),
          manual ? findsOneWidget : findsNothing,
        );
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
      expect(find.text('Placer le point moi-même'), findsOneWidget);

      // Reprendre la photo efface l'erreur et le repli.
      await tester.tap(find.text('Reprendre'));
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(find.text('Placer le point moi-même'), findsNothing);
    });
  });

  testWidgets('estimation en panne : la photo part sans estimation (NW-156)', (
    tester,
  ) async {
    var requests = 0;
    final result = await _openCameraScreen(
      tester,
      estimate: (_) async {
        requests++;
        return http.Response('', 503);
      },
    );

    await _takePhoto(tester);
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    final shownPhoto = tester.widget<Image>(find.byType(Image)).image;

    await tester.tap(find.text('Placer le point moi-même'));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.byType(CameraScreen), findsNothing);
    final draft = await result;
    expect(draft, isNotNull);
    expect(draft!.estimate, isNull);
    // Même photo, mêmes mesures : rien n'est perdu.
    expect((shownPhoto as MemoryImage).bytes, draft.capture.jpegBytes);
    expect(draft.initialLongitude, -4.4861);
    expect(draft.initialLatitude, 48.3904);
  });

  group('arrière-plan (NW-156)', () {
    testWidgets('libère la caméra puis en rouvre une neuve au retour', (
      tester,
    ) async {
      final cameras = <_FakeCamera>[];
      await _openCameraScreen(
        tester,
        createCamera: () {
          final camera = _FakeCamera();
          cameras.add(camera);
          return camera;
        },
      );
      expect(cameras, hasLength(1));

      // Masquée, l'app ne dessine plus : on ne vérifie que la caméra.
      _sendToBackground(tester);
      await tester.pump();
      expect(cameras.single.isDisposed, isTrue);

      _bringToForeground(tester);
      await tester.pump();
      expect(cameras, hasLength(2));
      expect(cameras.last.isDisposed, isFalse);
      expect(find.byKey(_previewKey), findsOneWidget);

      await _takePhoto(tester);
      expect(cameras.last.pictures, 1);
    });

    testWidgets('garde la photo prise pendant l’arrière-plan', (tester) async {
      await _openCameraScreen(tester);
      await _takePhoto(tester);

      _sendToBackground(tester);
      await tester.pump();
      _bringToForeground(tester);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
    });

    testWidgets('ouverture lente : la nouvelle caméra attend l’ancienne', (
      tester,
    ) async {
      final slowOpening = Completer<void>();
      final cameras = <_FakeCamera>[];
      await _openCameraScreen(
        tester,
        createCamera: () {
          // Seule la première ouverture traîne.
          final camera = _FakeCamera(
            opening: cameras.isEmpty ? slowOpening.future : null,
          );
          cameras.add(camera);
          return camera;
        },
        settle: false,
      );
      // Première image hors écran, puis animation d'ouverture.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      _sendToBackground(tester);
      await tester.pump();
      _bringToForeground(tester);
      await tester.pump(const Duration(seconds: 1));
      // La première caméra s'ouvre encore : pas de seconde caméra.
      expect(cameras, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Fin de l'ouverture, puis libération : la seconde peut s'ouvrir.
      slowOpening.complete();
      await tester.pumpAndSettle();
      expect(cameras, hasLength(2));
      expect(cameras.first.isReleased, isTrue);
      expect(cameras.last.isDisposed, isFalse);
      expect(find.byKey(_previewKey), findsOneWidget);
    });

    testWidgets('libération lente : pas de nouvelle caméra avant la fin', (
      tester,
    ) async {
      final slowRelease = Completer<void>();
      final cameras = <_FakeCamera>[];
      await _openCameraScreen(
        tester,
        createCamera: () {
          // Seule la première caméra met du temps à être rendue.
          final camera = _FakeCamera(
            release: cameras.isEmpty ? slowRelease.future : null,
          );
          cameras.add(camera);
          return camera;
        },
      );

      _sendToBackground(tester);
      await tester.pump();
      _bringToForeground(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(cameras.single.isDisposed, isTrue);
      expect(cameras.single.isReleased, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      slowRelease.complete();
      await tester.pumpAndSettle();
      expect(cameras, hasLength(2));
      expect(find.byKey(_previewKey), findsOneWidget);
    });

    testWidgets('masquée de nouveau avant la libération : une seule caméra', (
      tester,
    ) async {
      final slowRelease = Completer<void>();
      final cameras = <_FakeCamera>[];
      await _openCameraScreen(
        tester,
        createCamera: () {
          final camera = _FakeCamera(
            release: cameras.isEmpty ? slowRelease.future : null,
          );
          cameras.add(camera);
          return camera;
        },
      );

      // Deux allers-retours pendant que la première caméra se libère.
      for (var i = 0; i < 2; i++) {
        _sendToBackground(tester);
        await tester.pump();
        _bringToForeground(tester);
        await tester.pump();
      }

      slowRelease.complete();
      await tester.pumpAndSettle();
      expect(cameras, hasLength(2));
      expect(cameras.last.isDisposed, isFalse);
      expect(find.byKey(_previewKey), findsOneWidget);
    });

    testWidgets('fermeture pendant l’ouverture : caméra libérée', (
      tester,
    ) async {
      final slowOpening = Completer<void>();
      final camera = _FakeCamera(opening: slowOpening.future);
      await _openCameraScreen(tester, camera: camera, settle: false);
      // Première image hors écran, puis animation d'ouverture.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraScreen), findsNothing);
      expect(camera.isDisposed, isTrue);

      slowOpening.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('azimut de la caméra (NW-150)', () {
    testWidgets('Android : suit l’axe de visée, pas le haut du téléphone', (
      tester,
    ) async {
      // Haut du téléphone vers 100° : le cap de precise_compass ne doit pas
      // servir, seule sa déclinaison (+2°) est reprise.
      await _openCameraScreen(
        tester,
        cameraAxisService: _cameraAimingAt(magneticAzimuth: 30),
      );

      expect(find.text('±8 m · cap 32° · inclinaison -10°'), findsOneWidget);
    });

    testWidgets('Android : caméra vers le sol, la photo est bloquée', (
      tester,
    ) async {
      await _openCameraScreen(
        tester,
        cameraAxisService: _cameraAimingAt(magneticAzimuth: 0, pitch: -89),
      );

      expect(find.text('Relevez le téléphone vers l’horizon.'), findsOneWidget);
      expect(find.textContaining('cap'), findsNothing);
    });

    testWidgets('Android : capteur absent, la photo est bloquée', (
      tester,
    ) async {
      await _openCameraScreen(
        tester,
        cameraAxisService: CameraAxisService(
          rotationMatrices: Stream.error(StateError('unavailable')),
        ),
      );

      expect(
        find.text('Capteurs d’orientation indisponibles.'),
        findsOneWidget,
      );
    });

    testWidgets('iOS : garde le cap vrai de CoreLocation', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _openCameraScreen(tester);

        expect(find.text('±8 m · cap 102° · inclinaison -10°'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

const _previewKey = ValueKey('camera-preview');

/// Téléphone debout, sans roulis, caméra visant [magneticAzimuth] et
/// [pitch] degrés au-dessus de l'horizon (matrice Android, ligne par ligne).
CameraAxisService _cameraAimingAt({
  required double magneticAzimuth,
  double pitch = -10,
}) {
  final h = magneticAzimuth * math.pi / 180;
  final p = pitch * math.pi / 180;
  // Colonnes : axes x, y et z du téléphone dans le repère est/nord/haut.
  final x = [math.cos(h), -math.sin(h), 0.0];
  final z = [
    -math.sin(h) * math.cos(p),
    -math.cos(h) * math.cos(p),
    -math.sin(p),
  ];
  final y = [
    z[1] * x[2] - z[2] * x[1],
    z[2] * x[0] - z[0] * x[2],
    z[0] * x[1] - z[1] * x[0],
  ];
  return CameraAxisService(
    rotationMatrices: Stream.value([
      for (var row = 0; row < 3; row++) ...[x[row], y[row], z[row]],
    ]),
  );
}

/// Ouvre l'écran comme la carte, pour récupérer ce qu'il renvoie en se
/// fermant.
Future<Future<PhotoReportDraft?>> _openCameraScreen(
  WidgetTester tester, {
  _FakeCamera? camera,
  ReportCamera Function()? createCamera,
  MockClientHandler? estimate,
  CameraAxisService? cameraAxisService,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
            createCamera: createCamera ?? () => camera ?? _FakeCamera(),
            locationService: _FakeLocationService(),
            orientationService: _FakeOrientationService(),
            // Par défaut, caméra qui vise 245° vrais (243° magnétiques + 2°).
            cameraAxisService: defaultTargetPlatform == TargetPlatform.android
                ? cameraAxisService ?? _cameraAimingAt(magneticAzimuth: 243)
                : null,
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
  if (settle) await tester.pumpAndSettle();

  return result;
}

/// Écran verrouillé ou autre application, dans l'ordre des états réels.
void _sendToBackground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

void _bringToForeground(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
  _FakeCamera({this.opening, this.release});

  /// Fin de l'ouverture ; immédiate par défaut.
  final Future<void>? opening;

  /// Fin de la libération par le système ; immédiate par défaut.
  final Future<void>? release;
  int pictures = 0;

  /// Libération demandée.
  bool isDisposed = false;

  /// Caméra rendue au système.
  bool isReleased = false;

  @override
  Future<void> initialize() async => opening;

  @override
  Widget buildPreview() =>
      const ColoredBox(key: _previewKey, color: Colors.blueGrey);

  @override
  Future<Uint8List> takePicture() async {
    pictures++;
    // Focale de 4,25 mm dans les EXIF, comme un objectif principal.
    final photo = img.Image(width: 64, height: 48);
    photo.exif.exifIfd['FocalLength'] = img.IfdValueRational(425, 100);
    return img.encodeJpg(photo);
  }

  /// Comme DeviceReportCamera : la libération attend la fin de l'ouverture.
  @override
  Future<void> dispose() async {
    isDisposed = true;
    await opening;
    await release;
    isReleased = true;
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
        .copyWith(headingMagnetic: 100, headingTrue: 102, heading: 102),
  );
}
