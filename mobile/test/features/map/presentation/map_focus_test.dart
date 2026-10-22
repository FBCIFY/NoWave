import 'package:blueway/core/map/globe_pitch_controller.dart';
import 'package:blueway/core/map/map_config.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:blueway/features/alerts/data/alert_service.dart';
import 'package:blueway/features/alerts/domain/alert.dart';
import 'package:blueway/features/alerts/presentation/alerts_panel.dart';
import 'package:blueway/features/camera/domain/photo_capture.dart';
import 'package:blueway/features/camera/domain/photo_report_draft.dart';
import 'package:image/image.dart' as img;

import 'package:blueway/features/map/presentation/report_marker.dart' as badges;
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/data/manual_report_service.dart';

import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:blueway/features/reports/domain/report_reach.dart';
import 'package:blueway/features/reports/presentation/report_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../../alerts/support/alert_fixtures.dart';
import '../support/focus_fakes.dart';

PhotoReportDraft photoDraft() => PhotoReportDraft(
  capture: PhotoCapture(
    jpegBytes: Uint8List.fromList(
      img.encodeJpg(img.Image(width: 4, height: 4)),
    ),
    measurements: PhotoCaptureMeasurements(
      observerLongitude: 5.37,
      observerLatitude: 43.29,
      gpsAccuracyMeters: 5,
      azimuthDegrees: 90,
      inclinationDegrees: -10,
      cameraHeightMeters: 2.5,
      cameraHeightSource: 'default',
      cameraHeightUncertaintyMeters: 0.5,
      capturedAt: DateTime.now(),
    ),
  ),
  estimate: null,
);

class _Reports extends Fake implements ReportDetailService {
  final calls = <String>[];
  Completer<ReportDetail>? response;
  @override
  Future<ReportDetail> fetchReport(String id) async {
    calls.add(id);
    return response?.future ?? focusReport(id: id);
  }
}

class _Alerts extends Fake implements AlertService {
  @override
  Future<AlertPage> fetchPage({int page = 1, int limit = 20}) async =>
      AlertPage.fromJson(pageJson());
}

class _Publications extends Fake implements ManualReportService {
  final requests = <ManualReportRequest>[];
  @override
  Future<String> createReport(ManualReportRequest request) async {
    requests.add(request);
    return 'published-report';
  }
}

class _LateTiles extends Fake implements ReportTiles {
  final ready = Completer<void>();
  @override
  Future<void> addTo(mb.MapboxMap map) async {
    await ready.future;
    await map.style.addLayer(
      mb.SymbolLayer(
        id: ReportTiles.pointsLayerId,
        sourceId: ReportTiles.sourceId,
      ),
    );
  }
}

/// Hauteur de la carte dans la mise en page Flutter.
double mapHeight(WidgetTester tester) =>
    tester.getSize(find.byType(mb.MapWidget)).height;

/// Hauteur prise par la fiche en bas de la carte, marge comprise.
double panelHeight(WidgetTester tester) =>
    tester.getSize(find.byType(ReportDetailPanel)).height;

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late MapFocusController focus;
  late FocusGps gps;
  late FocusMap map;
  late _Reports reports;

  void focusTestWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      focus = MapFocusController();
      gps = FocusGps();
      map = FocusMap();
      reports = _Reports();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
        await gps.close();
      }
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  }

  void styleReady(WidgetTester tester) {
    tester
        .widget<mb.MapWidget>(find.byType(mb.MapWidget))
        .onStyleLoadedListener!(
      mb.StyleLoadedEventData.fromJson({
        'timeInterval': {'begin': 0, 'end': 1},
      }),
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    bool style = true,
    ReportTiles? tiles,
    bool reduceMotion = false,
    Future<PhotoReportDraft?> Function()? onOpenCamera,
    ManualReportService? publicationService,
    AlertService? alertService,
  }) async {
    await prepareFocusMarkers(tester);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: MapScreen(
          focusController: focus,
          locationService: gps,
          reportDetailService: reports,
          reportTiles: tiles,
          onOpenCamera: onOpenCamera,
          reportService: publicationService,
          alertService: alertService,
        ),
      ),
    );
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onMapCreated!(map);
    if (style) styleReady(tester);
    await pumpFrames(tester);
  }

  focusTestWidgets(
    'mouvement pendant conversion : refuse les coordonnées devenues anciennes',
    (tester) async {
      gps.initial.complete(focusPosition());
      final publications = _Publications();
      await mount(tester, publicationService: publications);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      await tester.tap(find.text('Pollution'));
      await tester.pump();
      final conversion = Completer<mb.Point>();
      map.onCoordinate = (_) => conversion.future;
      await tester.tap(find.text('Publier le signalement'));
      await tester.pump();
      tester
          .widget<mb.MapWidget>(find.byType(mb.MapWidget))
          .onCameraChangeListener!(
        mb.CameraChangedEventData.fromJson({
          'timestamp': 1,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [8.0, 44.0],
            },
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
            'zoom': 14.0,
            'bearing': 0.0,
            'pitch': 0.0,
          },
        }),
      );
      conversion.complete(mb.Point(coordinates: mb.Position(5, 43)));
      await pumpFrames(tester);
      expect(publications.requests, isEmpty);
      expect(find.textContaining('Position non confirmée.'), findsOneWidget);
    },
  );

  focusTestWidgets(
    'publication : attend la conversion courante avant de transmettre le point',
    (tester) async {
      gps.initial.complete(focusPosition());
      final publications = _Publications();
      await mount(tester, publicationService: publications);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      await tester.tap(find.text('Pollution'));
      await tester.pump();
      final conversion = Completer<mb.Point>();
      map.onCoordinate = (_) => conversion.future;
      await tester.tap(find.text('Publier le signalement'));
      await tester.pump();
      expect(publications.requests, isEmpty);
      conversion.complete(mb.Point(coordinates: mb.Position(5.375, 43.293)));
      await pumpFrames(tester);
      expect(publications.requests.single.longitude, 5.375);
      expect(publications.requests.single.latitude, 43.293);
    },
  );

  focusTestWidgets(
    'point à 3 km : publié sur le bord du cercle de 1 km, même direction',
    (tester) async {
      gps.initial.complete(focusPosition());
      final publications = _Publications();
      await mount(tester, publicationService: publications);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      expect(map.style.layers, contains('report-reach-outline'));
      final far = ReportReach.destination(43.29, 5.37, math.pi / 2, 3000);
      map.onCoordinate = (_) async =>
          mb.Point(coordinates: mb.Position(far.longitude, far.latitude));
      await tester.tap(find.text('Pollution'));
      await tester.pump();
      await tester.tap(find.text('Publier le signalement'));
      await pumpFrames(tester);
      final request = publications.requests.single;
      expect(
        ReportReach.distance(43.29, 5.37, request.latitude, request.longitude),
        closeTo(999, 1),
      );
      expect(request.latitude, closeTo(43.29, 0.001));
      expect(request.longitude, greaterThan(5.37));
      expect(map.style.layers, isNot(contains('report-reach-outline')));
    },
  );

  focusTestWidgets(
    'viseur lâché hors du cercle : la carte le ramène sur le bord',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      map.easedCameras.clear();
      final far = ReportReach.destination(43.29, 5.37, 0, 2500);
      map.onCoordinate = (_) async =>
          mb.Point(coordinates: mb.Position(far.longitude, far.latitude));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(mb.MapWidget)),
      );
      await gesture.moveBy(const Offset(0, 120));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await pumpFrames(tester);
      final center = map.easedCameras.last.center!.coordinates;
      expect(
        ReportReach.distance(
          43.29,
          5.37,
          center.lat.toDouble(),
          center.lng.toDouble(),
        ),
        closeTo(999, 1),
      );
      expect(center.lng.toDouble(), closeTo(5.37, 0.001));
    },
  );

  focusTestWidgets(
    'conversion en échec : aucun envoi et brouillon conservé pour réessayer',
    (tester) async {
      gps.initial.complete(focusPosition());
      final publications = _Publications();
      await mount(tester, publicationService: publications);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      await tester.tap(find.text('Pollution'));
      await tester.enterText(find.byType(TextField), 'Brouillon');
      map.onCoordinate = (_) async => throw StateError('conversion native');
      await tester.tap(find.text('Publier le signalement'));
      await pumpFrames(tester);
      expect(publications.requests, isEmpty);
      expect(find.textContaining('Position non confirmée.'), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      map.onCoordinate = null;
      await tester.tap(find.text('Publier le signalement'));
      await pumpFrames(tester);
      expect(publications.requests.single.description, 'Brouillon');
    },
  );

  focusTestWidgets(
    'une ancienne photo ne rouvre pas le formulaire après un autre parcours',
    (tester) async {
      gps.initial.complete(focusPosition());
      final camera = Completer<PhotoReportDraft?>();
      await mount(tester, onOpenCamera: () => camera.future);
      await tester.tap(find.byTooltip('Signaler avec une photo'));
      await tester.pump();
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await pumpFrames(tester);
      expect(find.byType(ReportComposerSheet), findsNothing);
      camera.complete(photoDraft());
      await pumpFrames(tester);
      expect(find.byType(ReportComposerSheet), findsNothing);
      expect(focus.isBlocked, isFalse);
    },
  );

  focusTestWidgets(
    'mouvements réduits : ferme le formulaire sans animer la restauration',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester, reduceMotion: true);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      expect(find.byType(ReportComposerSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Fermer'));
      await pumpFrames(tester);
      expect(map.easedCameras, isEmpty);
      expect(map.cameras, isNotEmpty);
    },
  );

  focusTestWidgets(
    'une route au-dessus suspend les traitements visuels jusqu’au retour',
    (tester) async {
      const channel =
          'dev.flutter.pigeon.mapbox_maps_flutter._OfflineSwitch.setMapboxStackConnected';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final connected = <Object?>[];
      messenger.setMockMessageHandler(channel, (message) async {
        final arguments =
            const StandardMessageCodec().decodeMessage(message) as List;
        connected.add(arguments.first);
        return const StandardMessageCodec().encodeMessage(<Object?>[null]);
      });
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      final tiles = _LateTiles()..ready.complete();
      gps.initial.complete(focusPosition());
      await mount(tester, tiles: tiles);
      final navigator = Navigator.of(tester.element(find.byType(MapScreen)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Profil')),
          ),
        ),
      );
      await pumpFrames(tester);
      // Mapbox perd le réseau tant que la carte est cachée.
      expect(connected.last, isFalse);
      navigator.pop();
      await pumpFrames(tester);
      expect(connected.last, isTrue);
    },
  );

  focusTestWidgets(
    'fermer le bandeau conserve un avertissement de couche indisponible',
    (tester) async {
      final tiles = _LateTiles();
      gps.initial.complete(focusPosition());
      await mount(tester, tiles: tiles);
      tiles.ready.completeError(StateError('réseau indisponible'));
      await pumpFrames(tester);
      final detailed = find.text(
        'Signalements indisponibles. Nouvel essai automatique.',
      );
      expect(detailed, findsOneWidget);
      await tester.tap(detailed);
      await pumpFrames(tester);
      expect(find.text('Signalements indisponibles'), findsOneWidget);
      await tester.tap(find.text('Signalements indisponibles'));
      await pumpFrames(tester);
      expect(find.text('Signalements indisponibles'), findsOneWidget);
    },
  );

  focusTestWidgets(
    'MVT en retard : sélection visible puis replacée au-dessus',
    (tester) async {
      final tiles = _LateTiles();
      gps.initial.complete(focusPosition());
      await mount(tester, tiles: tiles);
      final pending = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await pending;
      expect(map.style.layers, contains('alert-selected-point'));
      expect(map.style.layers, isNot(contains(ReportTiles.pointsLayerId)));
      tiles.ready.complete();
      await pumpFrames(tester);
      expect(
        map.style.layerOrder.indexOf('alert-selected-point'),
        greaterThan(map.style.layerOrder.indexOf(ReportTiles.pointsLayerId)),
      );
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets(
    'Mes alertes : vise le signalement seul, même inclinaison, en une animation',
    (tester) async {
      gps.initial.complete(focusPosition());
      map
        ..cameraBearing = 130
        ..cameraPitch = 30;
      await mount(tester);
      focus.focus(focusReport(longitude: 6));
      await pumpFrames(tester);
      expect(focus.origin, MapFocusOrigin.history);
      // La fiche couvre le bas : pas de cadrage à deux points.
      expect(map.fittedCoordinates, isEmpty);
      expect(map.easedCameras, hasLength(1));
      final camera = map.easedCameras.single;
      expect(camera.center!.coordinates.lng, 6);
      // Zoom proche et inclinaison choisie gardés.
      expect(camera.zoom, 14);
      expect(camera.bearing, 130);
      expect(camera.pitch, 30);
      expect(camera.padding!.bottom, mapHeight(tester) / 2);
      expect(map.animationDurations.single, inInclusiveRange(240, 500));
      expect(
        tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).viewport,
        isA<mb.IdleViewportState>(),
      );
    },
  );

  focusTestWidgets('fiche ouverte : inclinaison plafonnée à 63,75°', (
    tester,
  ) async {
    map.cameraPitch = 70;
    await mount(tester);
    focus.focus(focusReport(), origin: MapFocusOrigin.mapTap);
    await pumpFrames(tester);
    expect(map.easedCameras.single.pitch, GlobePitchController.defaultPitch);
    expect(map.easedCameras.single.zoom, 14);
  });

  focusTestWidgets('ouvrir un report conserve le cap et l’inclinaison', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    map.cameraBearing = 130;
    map.cameraPitch = 45;
    await mount(tester);
    final done = focus.focusAlert(focusReport());
    await pumpFrames(tester);
    await done;
    expect(map.fitCameraOptions.single.bearing, 130);
    expect(map.fitCameraOptions.single.pitch, 45);
    expect(map.easedCameras.single.bearing, 130);
    expect(map.easedCameras.single.pitch, 45);
  });

  focusTestWidgets('sélection masquée : attend le retour de la carte', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester);
    final navigator = Navigator.of(tester.element(find.byType(MapScreen)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Écran opaque')),
        ),
      ),
    );
    await pumpFrames(tester);
    focus.focus(focusReport());
    await pumpFrames(tester);
    expect(map.cameras, isEmpty);
    navigator.pop();
    await pumpFrames(tester);
    expect(map.easedCameras, hasLength(1));
  });

  for (final photo in [false, true]) {
    focusTestWidgets(
      'NW-210 ${photo ? 'photo' : 'manuel'} : même cadrage GPS et geste libre',
      (tester) async {
        gps.initial.complete(focusPosition());
        await mount(tester);
        final pending = focus.focusAlert(
          focusReport(
            longitude: 6,
            photo: photo
                ? const ReportPhoto(
                    status: ReportPhotoStatus.pending,
                    url: null,
                  )
                : null,
          ),
        );
        await pumpFrames(tester);
        await pending;
        expect(
          map.fittedCoordinates.single.map((point) => point.coordinates.lng),
          [6, 5.37],
        );
        expect(map.location.settings.last.enabled, true);
        expect(find.byType(ReportDetailSheet), findsNothing);
        await tester.tapAt(const Offset(200, 300));
        gps.positions.add(focusPosition(longitude: 7));
        await pumpFrames(tester);
        expect(map.cameras, hasLength(1));
      },
    );
  }

  for (final category in ReportCategory.values) {
    focusTestWidgets('badge sélectionné ${category.apiValue} sans MVT', (
      tester,
    ) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      final pending = focus.focusAlert(focusReport(category: category));
      await pumpFrames(tester);
      await pending;
      final layer = map.style.layers['alert-selected-point']!;
      expect(layer['type'], 'symbol');
      // Caché au dézoom, comme les badges, au profit de la zone colorée.
      expect(layer['minzoom'], ReportTiles.badgesMinZoom);
      // Un peu plus gros que les badges des tuiles, sur un halo blanc.
      expect(
        layer['layout']['icon-size'],
        ReportTiles.markerSizeExpression(scale: 1.35),
      );
      final halo = map.style.layers['alert-selected-halo']!;
      expect(halo['type'], 'circle');
      expect(halo['minzoom'], ReportTiles.badgesMinZoom);
      expect(
        map.style.layerOrder.indexOf('alert-selected-halo'),
        map.style.layerOrder.indexOf('alert-selected-point') - 1,
      );
      expect(
        layer['layout']['icon-image'],
        contains(badges.ReportMarker.imageId(category)),
      );
      final data = jsonDecode(
        map.style.sources['alert-selected']!['data'] as String,
      );
      expect(data['properties']['category'], category.apiValue);
      final image = map.style.images[badges.ReportMarker.imageId(category)]!;
      expect(image.data, await badges.ReportMarker.paintCategory(category));
      expect(map.style.layerOrder.last, 'alert-selected-point');
      expect(find.byType(ReportDetailSheet), findsNothing);
    });
  }

  focusTestWidgets('style rechargé et rappels idempotents : badge restauré', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester);
    final pending = focus.focusAlert(
      focusReport(category: ReportCategory.marineAnimal),
    );
    await pumpFrames(tester);
    await pending;
    map.style.images.clear();
    map.style.layers.clear();
    map.style.sources.clear();
    map.style.layerOrder.clear();
    styleReady(tester);
    styleReady(tester);
    await pumpFrames(tester);
    expect(map.style.layers.keys.where((id) => id.startsWith('alert-')), [
      'alert-selected-halo',
      'alert-selected-point',
    ]);
    expect(map.style.sources.keys.where((id) => id.startsWith('alert-')), [
      'alert-selected',
    ]);
    expect(
      map.style.images.keys.where((id) => id.startsWith('nowave-report-')),
      [badges.ReportMarker.imageId(ReportCategory.marineAnimal)],
    );
    expect(map.cameras, hasLength(1));
  });

  focusTestWidgets(
    'catégorie changée pendant enregistrement : une seule sélection finale',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      final slow = Completer<void>();
      map.style.imageGate = slow.future;
      final first = focus.focusAlert(
        focusReport(category: ReportCategory.marineAnimal),
      );
      await pumpFrames(tester);
      final second = focus.focusAlert(
        focusReport(
          id: 'b',
          longitude: 7,
          category: ReportCategory.obstruction,
        ),
      );
      map.style.imageGate = null;
      slow.complete();
      await pumpFrames(tester);
      await Future.wait([first, second]);
      final data = jsonDecode(
        map.style.sources['alert-selected']!['data'] as String,
      );
      expect(data['properties'], {'report_id': 'b', 'category': 'obstruction'});
      expect(data['geometry']['coordinates'], [7, 43.29]);
      expect(map.style.layers.keys.where((id) => id.startsWith('alert-')), [
        'alert-selected-halo',
        'alert-selected-point',
      ]);
      expect(map.cameras, hasLength(1));
      focus.clear();
      await pumpFrames(tester);
      expect(map.style.layers, isNot(contains('alert-selected-point')));
      expect(map.style.layers, isNot(contains('alert-selected-halo')));
      expect(map.style.sources, isNot(contains('alert-selected')));
      styleReady(tester);
      await pumpFrames(tester);
      expect(map.style.layers, isNot(contains('alert-selected-point')));
    },
  );

  focusTestWidgets('expiration après affichage : couche et source retirées', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester);
    final pending = focus.focusAlert(
      focusReport(expires: DateTime.now().add(const Duration(seconds: 2))),
    );
    await pumpFrames(tester);
    await pending;
    expect(map.style.layers, contains('alert-selected-point'));
    await tester.pump(const Duration(seconds: 3));
    await pumpFrames(tester);
    expect(map.style.layers, isNot(contains('alert-selected-point')));
    expect(map.style.layers, isNot(contains('alert-selected-halo')));
    expect(map.style.sources, isNot(contains('alert-selected')));
  });

  focusTestWidgets(
    'deux points cadrés, puck neutre visible, aucun suivi GPS repris',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      final completed = focus.focusAlert(focusReport(longitude: 6));
      await pumpFrames(tester);
      await completed;
      expect(map.fittedCoordinates.single.map((p) => p.coordinates.lng), [
        6,
        5.37,
      ]);
      expect(map.style.layers, contains('alert-selected-point'));
      // Le repère reste celui du réglage courant : flèche native ou point
      // caché sous le chevron.
      final puck = MapConfig.locationPuckSettings();
      expect(map.location.settings.last.enabled, true);
      expect(
        map.location.settings.last.puckBearingEnabled,
        puck.puckBearingEnabled,
      );
      expect(
        map.location.settings.last.locationPuck!.locationPuck3D?.modelUri,
        puck.locationPuck!.locationPuck3D?.modelUri,
      );
      expect(
        tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).viewport,
        isA<mb.IdleViewportState>(),
      );
      expect(find.byType(ReportDetailSheet), findsNothing);
      gps.positions.add(focusPosition(longitude: 7));
      await pumpFrames(tester);
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets('carte non prête : conserve la sélection jusqu’au style', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester, style: false);
    var complete = false;
    final pending = focus
        .focusAlert(focusReport())
        .then((_) => complete = true);
    await pumpFrames(tester);
    expect(complete, false);
    expect(map.cameras, isEmpty);
    styleReady(tester);
    await pumpFrames(tester);
    await pending;
    expect(map.cameras, hasLength(1));
  });

  focusTestWidgets(
    'timeout GPS : repli persistant puis un seul cadrage à l’arrivée GPS',
    (tester) async {
      await mount(tester);
      final pending = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await pending;
      expect(map.cameras.single.zoom, 16);
      expect(
        find.text('Position indisponible — cadrage sur le signalement'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text('Position indisponible — cadrage sur le signalement'),
        findsOneWidget,
      );
      gps.initial.completeError(TimeoutException('first fix'));
      await pumpFrames(tester);
      gps.positions.add(focusPosition());
      await pumpFrames(tester);
      expect(map.cameras, hasLength(2));
      expect(map.fittedCoordinates, hasLength(1));
      expect(
        find.text('Position indisponible — cadrage sur le signalement'),
        findsNothing,
      );
      gps.positions.add(focusPosition(longitude: 8));
      await pumpFrames(tester);
      expect(map.cameras, hasLength(2));
    },
  );

  focusTestWidgets('geste manuel avant GPS tardif : aucune caméra imposée', (
    tester,
  ) async {
    await mount(tester);
    final pending = focus.focusAlert(focusReport());
    await pumpFrames(tester);
    await pending;
    await tester.tapAt(const Offset(200, 300));
    gps.initial.complete(focusPosition());
    await pumpFrames(tester);
    expect(map.cameras, hasLength(1));
    expect(
      tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).viewport,
      isA<mb.IdleViewportState>(),
    );
  });

  focusTestWidgets(
    'GPS refusé puis autorisé au retour : recadre une fois sans suivi',
    (tester) async {
      gps.allowed = false;
      await mount(tester);
      gps.initial.completeError(StateError('Permission refusée'));
      final pending = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await pending;
      expect(map.cameras.single.zoom, 16);
      gps.allowed = true;
      gps.onCurrent = () async => focusPosition();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await pumpFrames(tester);
      expect(map.cameras, hasLength(2));
      expect(map.fittedCoordinates, hasLength(1));
      expect(
        tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).viewport,
        isA<mb.IdleViewportState>(),
      );
    },
  );

  focusTestWidgets(
    'repère indépendant des MVT : fiche seulement après tap volontaire',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      final pending = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await pending;
      expect(reports.calls, isEmpty);
      expect(find.byType(ReportDetailSheet), findsNothing);
      final mapListener = tester.widget<Listener>(
        find
            .ancestor(
              of: find.byType(mb.MapWidget),
              matching: find.byType(Listener),
            )
            .first,
      );
      final interaction = map.interactions.singleWhere(
        (interaction) =>
            interaction.featuresetDescriptor?.layerId == 'alert-selected-point',
      );
      interaction.action(
        mb.TypedFeaturesetFeature(
          mb.FeaturesetDescriptor(layerId: 'alert-selected-point'),
          {
            'type': 'Point',
            'coordinates': [5.373, 43.29],
          },
          {'report_id': 'report-a'},
          {},
        ),
        mb.MapContentGestureContext(
          touchPosition: mb.ScreenCoordinate(x: 200, y: 300),
          point: mb.Point(coordinates: mb.Position(5.373, 43.29)),
          gestureState: mb.GestureState.ended,
        ),
      );
      // iOS can deliver the native feature callback before Flutter's pointer
      // event for the selecting touch. This touch is not a cancellation.
      mapListener.onPointerDown!(
        const PointerDownEvent(position: Offset(200, 300)),
      );
      await pumpFrames(tester);
      expect(reports.calls, ['report-a']);
      expect(find.byType(ReportDetailSheet), findsOneWidget);
      expect(focus.origin, MapFocusOrigin.mapTap);
      // Le repère de la notification est celui qu'on vient de toucher.
      expect(map.style.layers, contains('alert-selected-point'));
      expect(map.easedCameras, hasLength(2));
      expect(map.easedCameras.last.padding!.bottom, greaterThan(150));
    },
  );

  focusTestWidgets(
    'tap chargé lentement : cadrage au-dessus de la fiche, GPS tardif sans suivi',
    (tester) async {
      await mount(tester);
      reports.response = Completer<ReportDetail>();
      map.interactions
          .firstWhere((interaction) => interaction.featuresetDescriptor != null)
          .action(
            mb.TypedFeaturesetFeature(
              mb.FeaturesetDescriptor(layerId: 'alert-selected-point'),
              {
                'type': 'Point',
                'coordinates': [5.373, 43.29],
              },
              {'report_id': 'report-a'},
              {},
            ),
            mb.MapContentGestureContext(
              touchPosition: mb.ScreenCoordinate(x: 200, y: 300),
              point: mb.Point(coordinates: mb.Position(5.373, 43.29)),
              gestureState: mb.GestureState.ended,
            ),
          );
      await pumpFrames(tester);
      expect(map.cameras, isEmpty);
      reports.response!.complete(focusReport());
      await pumpFrames(tester);
      expect(focus.origin, MapFocusOrigin.mapTap);
      // Le badge touché est mis en valeur au-dessus de celui des tuiles.
      expect(map.style.layers, contains('alert-selected-point'));
      expect(map.style.layers, contains('alert-selected-halo'));
      expect(map.easedCameras, hasLength(1));
      expect(map.easedCameras.single.padding!.bottom, panelHeight(tester));
      gps.initial.complete(focusPosition());
      await pumpFrames(tester);
      expect(map.easedCameras, hasLength(1));
      expect(
        tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).viewport,
        isA<mb.IdleViewportState>(),
      );
    },
  );

  mb.MapContentGestureContext touch() => mb.MapContentGestureContext(
    touchPosition: mb.ScreenCoordinate(x: 200, y: 300),
    point: mb.Point(coordinates: mb.Position(5.373, 43.29)),
    gestureState: mb.GestureState.ended,
  );

  void tapBadge(String id, {double longitude = 5.373}) {
    map.interactions
        .firstWhere((interaction) => interaction.featuresetDescriptor != null)
        .action(
          mb.TypedFeaturesetFeature(
            mb.FeaturesetDescriptor(layerId: ReportTiles.pointsLayerId),
            {
              'type': 'Point',
              'coordinates': [longitude, 43.29],
            },
            {'report_id': id},
            {},
          ),
          touch(),
        );
  }

  void tapMap() => map.interactions
      .singleWhere((interaction) => interaction.featuresetDescriptor == null)
      .action(null, touch());

  focusTestWidgets('toucher la carte ferme la fiche sans restaurer la caméra', (
    tester,
  ) async {
    await mount(tester);
    tapBadge('report-a');
    await pumpFrames(tester);
    final cameras = map.easedCameras.length;
    final surface = find.byKey(const ValueKey('map-panel-surface'));
    final initialY = tester.getTopLeft(surface).dy;
    tapMap();
    await tester.pump();
    // Le panneau reste monté pendant sa sortie : aucun retrait brutal.
    expect(find.byType(ReportDetailPanel), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(surface).dy, greaterThan(initialY));
    await pumpFrames(tester);
    expect(find.byType(ReportDetailPanel), findsNothing);
    expect(focus.report, isNull);
    expect(map.easedCameras, hasLength(cameras));
    expect(map.style.layers, isNot(contains('alert-selected-point')));
  });

  focusTestWidgets(
    'autre report pendant la sortie : sa nouvelle fiche reste ouverte',
    (tester) async {
      await mount(tester);
      tapBadge('report-a');
      await pumpFrames(tester);
      tapMap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      tapBadge('report-b');
      await pumpFrames(tester);
      expect(find.byType(ReportDetailPanel), findsOneWidget);
      expect(
        tester
            .widget<ReportDetailSheet>(find.byType(ReportDetailSheet))
            .reportId,
        'report-b',
      );
      expect(focus.report?.id, 'report-b');
    },
  );

  focusTestWidgets(
    'fiche fermée pendant le chargement : aucun cadrage tardif',
    (tester) async {
      await mount(tester);
      reports.response = Completer<ReportDetail>();
      tapBadge('report-a');
      await pumpFrames(tester);
      tapMap();
      reports.response!.complete(focusReport());
      await pumpFrames(tester);
      expect(find.byType(ReportDetailPanel), findsNothing);
      expect(focus.report, isNull);
      expect(map.easedCameras, isEmpty);
    },
  );

  focusTestWidgets('Mes alertes : toucher le fond ferme aussi la liste seule', (
    tester,
  ) async {
    await mount(tester, alertService: _Alerts());
    await tester.tap(find.byTooltip('Mes alertes'));
    await pumpFrames(tester);
    expect(find.byType(AlertsPanel), findsOneWidget);
    tapMap();
    await pumpFrames(tester);
    expect(find.byType(AlertsPanel), findsNothing);
    expect(map.easedCameras, isEmpty);
  });

  focusTestWidgets('toucher les détails ne ferme pas le panneau', (
    tester,
  ) async {
    await mount(tester);
    tapBadge('report-a');
    await pumpFrames(tester);
    await tester.tap(find.byType(ReportDetailSheet));
    await pumpFrames(tester);
    expect(find.byType(ReportDetailPanel), findsOneWidget);
  });

  focusTestWidgets('fiche fermée : la carte revient comme avant', (
    tester,
  ) async {
    map
      ..cameraZoom = 9.25
      ..cameraPitch = 10
      ..cameraBearing = 20;
    await mount(tester);
    tapBadge('report-a');
    await pumpFrames(tester);
    // Fiche posée en bas, sans voile, et boutons de la carte masqués.
    expect(find.byType(ReportDetailPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Créer un signalement'), findsNothing);
    final detail = map.easedCameras.single;
    expect(detail.zoom, 14);
    expect(detail.pitch, 10);
    expect(detail.padding!.bottom, panelHeight(tester));

    // La fiche se ferme au geste ou au retour système, sans croix.
    expect(find.byTooltip('Fermer'), findsNothing);
    await tester.fling(
      find.byKey(const ValueKey('map-panel-drag-handle')),
      const Offset(0, 400),
      900,
    );
    await pumpFrames(tester);
    expect(find.byType(ReportDetailPanel), findsNothing);
    expect(find.byTooltip('Créer un signalement'), findsOneWidget);
    expect(map.style.layers, isNot(contains('alert-selected-point')));
    expect(map.style.layers, isNot(contains('alert-selected-halo')));
    expect(
      map.easedCameras.where((camera) => camera.zoom == 9.25),
      hasLength(1),
    );
    final restored = map.easedCameras.last;
    expect(restored.center!.coordinates.lng, 5.37);
    expect(restored.zoom, 9.25);
    expect(restored.pitch, 10);
    expect(restored.bearing, 20);
    expect(restored.padding!.bottom, 0);
  });

  focusTestWidgets('déplacer la carte ferme la fiche sans restaurer la vue', (
    tester,
  ) async {
    await mount(tester);
    tapBadge('report-a');
    await pumpFrames(tester);
    expect(map.easedCameras, hasLength(1));
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onScrollListener!(
      touch(),
    );
    await pumpFrames(tester);
    expect(find.byType(ReportDetailPanel), findsNothing);
    expect(map.style.layers, isNot(contains('alert-selected-point')));
    // Pas de retour à la vue d'avant : seul le décalage de la fiche part.
    expect(
      map.easedCameras.where((camera) => camera.zoom != null),
      hasLength(1),
    );
  });

  focusTestWidgets(
    'fermeture par la carte : aucun zoom renvoyé au relâchement',
    (tester) async {
      await mount(tester);
      tapBadge('report-a');
      await pumpFrames(tester);
      expect(map.easedCameras.single.zoom, 13);
      map.cameras.clear();
      map.easedCameras.clear();

      final gesture = await tester.startGesture(const Offset(220, 200));
      final mapWidget = tester.widget<mb.MapWidget>(find.byType(mb.MapWidget));
      mapWidget.onZoomListener!(touch());
      // Le zoom appartient aux doigts puis à l'inertie native.
      map.cameraZoom = 11.25;
      mapWidget.onCameraChangeListener!(
        mb.CameraChangedEventData.fromJson({
          'timestamp': 1,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [5.38, 43.30],
            },
            'zoom': 11.25,
            'pitch': 35.0,
            'bearing': 20.0,
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 240.0, 'right': 0.0},
          },
        }),
      );
      await pumpFrames(tester);
      expect(find.byType(ReportDetailPanel), findsNothing);
      await gesture.up();
      await pumpFrames(tester);
      expect(map.easedCameras, isEmpty);
      expect(map.cameras.where((camera) => camera.zoom != null), isEmpty);
      expect(map.cameras.last.padding!.bottom, 0);
    },
  );

  focusTestWidgets(
    'fiche qui grandit : le signalement reste au milieu de la carte visible',
    (tester) async {
      reports.response = Completer<ReportDetail>()
        ..complete(
          focusReport(
            photo: const ReportPhoto(
              status: ReportPhotoStatus.uploaded,
              url: 'https://photo.test/report-a',
            ),
          ),
        );
      await mount(tester);
      tapBadge('report-a');
      await pumpFrames(tester);
      final first = map.easedCameras.single;
      expect(first.padding!.bottom, panelHeight(tester));
      expect(panelHeight(tester), lessThanOrEqualTo(mapHeight(tester) / 2));

      // Le contenu tiré vers le haut agrandit la fiche, pas le zoom.
      final surface = find.byKey(const ValueKey('map-panel-surface'));
      await tester.dragFrom(
        tester.getTopLeft(surface) + const Offset(200, 120),
        const Offset(0, -200),
      );
      await pumpFrames(tester);
      final grown = map.easedCameras.last;
      expect(map.easedCameras.length, greaterThan(1));
      expect(grown.padding!.bottom, panelHeight(tester));
      expect(grown.padding!.bottom, greaterThan(first.padding!.bottom));
      expect(grown.center!.coordinates.lng, 5.373);
      expect(grown.zoom, first.zoom);

      // Carte déplacée à la main : plus de recalage.
      final cameraCount = map.easedCameras.length;
      tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onScrollListener!(
        touch(),
      );
      await pumpFrames(tester);
      expect(map.easedCameras, hasLength(cameraCount));
      expect(find.byType(ReportDetailPanel), findsNothing);
    },
  );

  focusTestWidgets(
    'autre badge touché : la fiche change, la vue d’avant reste la première',
    (tester) async {
      map.cameraPitch = 30;
      await mount(tester);
      tapBadge('report-a');
      await pumpFrames(tester);
      tapBadge('report-b', longitude: 6);
      await pumpFrames(tester);
      expect(reports.calls, ['report-a', 'report-b']);
      expect(
        tester
            .widget<ReportDetailSheet>(find.byType(ReportDetailSheet))
            .reportId,
        'report-b',
      );
      expect(map.easedCameras.last.pitch, 30);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(map.easedCameras.last.pitch, 30);
      expect(map.easedCameras.last.zoom, 14);
    },
  );

  focusTestWidgets('notification pendant la fiche : la fiche se ferme', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester);
    tapBadge('report-a');
    await pumpFrames(tester);
    expect(find.byType(ReportDetailPanel), findsOneWidget);
    final pending = focus.focusAlert(focusReport(id: 'n', longitude: 6));
    await pumpFrames(tester);
    await pending;
    expect(find.byType(ReportDetailPanel), findsNothing);
    expect(map.fittedCoordinates, hasLength(1));
    expect(
      map.style.sources['alert-selected']!['data'],
      contains('"report_id":"n"'),
    );
  });

  focusTestWidgets(
    'Mes alertes : liste et détail en bas, même zoom, retour puis fermeture',
    (tester) async {
      map
        ..cameraPitch = 10
        ..cameraBearing = 20;
      await mount(tester, alertService: _Alerts());
      await tester.tap(find.byTooltip('Mes alertes'));
      await pumpFrames(tester);
      // Liste posée en bas, sans voile ; la carte ne bouge pas.
      expect(find.byType(AlertsPanel), findsOneWidget);
      expect(find.byTooltip('Mes alertes'), findsNothing);
      expect(find.byTooltip('Créer un signalement'), findsNothing);
      expect(
        tester.getRect(find.byType(AlertsPanel)).bottom,
        mapHeight(tester),
      );
      expect(map.easedCameras, isEmpty);

      await tester.tap(find.byKey(const ValueKey('alert-a')));
      await pumpFrames(tester);
      expect(reports.calls, ['report-a']);
      expect(find.byType(AlertsPanel), findsNothing);
      expect(find.byType(ReportDetailPanel), findsOneWidget);
      expect(
        tester.getRect(find.byType(ReportDetailPanel)).bottom,
        mapHeight(tester),
      );
      expect(focus.origin, MapFocusOrigin.history);
      // Même fiche que depuis la carte : le signalement reste au-dessus.
      final detail = map.easedCameras.single;
      expect(detail.padding!.top, 0);
      expect(detail.padding!.bottom, panelHeight(tester));
      expect(detail.zoom, 13);
      expect(detail.center!.coordinates.lng, 5.373);

      // Flèche de retour : la liste revient, la carte reste où elle est.
      await tester.tap(find.byTooltip('Retour'));
      await pumpFrames(tester);
      expect(find.byType(AlertsPanel), findsOneWidget);
      expect(find.byType(ReportDetailPanel), findsNothing);
      expect(map.style.layers, isNot(contains('alert-selected-point')));
      expect(
        map.easedCameras.where((camera) => camera.zoom != null),
        hasLength(1),
      );

      // Retour système sur la liste : la vue d'avant Mes alertes revient.
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      expect(find.byType(AlertsPanel), findsNothing);
      expect(find.byTooltip('Créer un signalement'), findsOneWidget);
      final restored = map.easedCameras.last;
      expect(restored.zoom, 14);
      expect(restored.pitch, 10);
      expect(restored.bearing, 20);
      expect(restored.padding!.top, 0);
    },
  );

  focusTestWidgets('Mes alertes : déplacer la carte ferme tous les panneaux', (
    tester,
  ) async {
    await mount(tester, alertService: _Alerts());
    await tester.tap(find.byTooltip('Mes alertes'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('alert-a')));
    await pumpFrames(tester);
    expect(map.easedCameras, hasLength(1));
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onScrollListener!(
      touch(),
    );
    await pumpFrames(tester);
    expect(find.byType(AlertsPanel), findsNothing);
    expect(find.byType(ReportDetailPanel), findsNothing);
    expect(focus.report, isNull);
    expect(
      map.easedCameras.where((camera) => camera.zoom != null),
      hasLength(1),
    );
  });

  focusTestWidgets('notification pendant Mes alertes : la liste se ferme', (
    tester,
  ) async {
    gps.initial.complete(focusPosition());
    await mount(tester, alertService: _Alerts());
    await tester.tap(find.byTooltip('Mes alertes'));
    await pumpFrames(tester);
    final pending = focus.focusAlert(focusReport(id: 'n', longitude: 6));
    await pumpFrames(tester);
    await pending;
    expect(find.byType(AlertsPanel), findsNothing);
    expect(map.fittedCoordinates, hasLength(1));
  });

  focusTestWidgets(
    'action Historique : la carte ouvre Mes alertes, refusée si bloquée',
    (tester) async {
      await mount(tester, alertService: _Alerts());
      focus.setBlocked(true);
      expect(focus.openAlerts(), isFalse);
      await pumpFrames(tester);
      expect(find.byType(AlertsPanel), findsNothing);
      focus.setBlocked(false);
      expect(focus.openAlerts(), isTrue);
      await pumpFrames(tester);
      expect(find.byType(AlertsPanel), findsOneWidget);
    },
  );

  focusTestWidgets(
    'expiration pendant attente du style : aucun point ni cadrage',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester, style: false);
      final report = focusReport(
        expires: DateTime.now().add(const Duration(seconds: 1)),
      );
      final failed = expectLater(
        focus.focusAlert(report),
        throwsA(isA<ReportNotFoundException>()),
      );
      await tester.pump(const Duration(seconds: 2));
      await failed;
      styleReady(tester);
      await pumpFrames(tester);
      expect(map.cameras, isEmpty);
      expect(map.style.layers, isNot(contains('alert-selected-point')));
    },
  );

  focusTestWidgets(
    'deux sélections pendant un calcul lent : seule la dernière caméra s’applique',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      final slow = Completer<mb.CameraOptions>();
      map.onFit = () => slow.future;
      final first = focus.focusAlert(focusReport(id: 'a', longitude: 6));
      await pumpFrames(tester);
      final second = focus.focusAlert(focusReport(id: 'b', longitude: 7));
      map.onFit = null;
      slow.complete(
        mb.CameraOptions(
          center: mb.Point(coordinates: mb.Position(6, 43)),
          zoom: 8,
        ),
      );
      await pumpFrames(tester);
      await Future.wait([first, second]);
      expect(map.cameras, hasLength(1));
      expect(map.cameras.single.center!.coordinates.lng, 7);
      expect(
        map.style.sources['alert-selected']!['data'],
        contains('"report_id":"b"'),
      );
    },
  );

  focusTestWidgets(
    'échec natif remonte au demandeur et réessai explicite fonctionne',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      map.onFit = () async => throw StateError('native camera');
      final failed = expectLater(
        focus.focusAlert(focusReport()),
        throwsStateError,
      );
      await pumpFrames(tester);
      await failed;
      map.onFit = null;
      final retry = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await retry;
      expect(map.cameras, hasLength(1));
    },
  );

  focusTestWidgets(
    'session invalidée pendant le calcul : aucune caméra appliquée',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      var authorized = true;
      final slow = Completer<mb.CameraOptions>();
      map.onFit = () => slow.future;
      final pending = focus.focusAlert(
        focusReport(),
        isCurrent: () => authorized,
      );
      await pumpFrames(tester);
      authorized = false;
      slow.complete(
        mb.CameraOptions(
          center: mb.Point(coordinates: mb.Position(6, 43)),
          zoom: 8,
        ),
      );
      await pumpFrames(tester);
      expect(map.cameras, isEmpty);
      expect(focus.report, isNull);
      await pending;
    },
  );

  focusTestWidgets(
    'échec du cadrage GPS tardif : réessai explicite sans boucle',
    (tester) async {
      await mount(tester);
      final pending = focus.focusAlert(focusReport());
      await pumpFrames(tester);
      await pending;
      map.onFit = () async => throw StateError('late camera');
      gps.initial.complete(focusPosition());
      await pumpFrames(tester);
      expect(find.text('Impossible de cadrer la carte.'), findsOneWidget);
      expect(map.cameras, hasLength(1));
      gps.positions.add(focusPosition(longitude: 5.38));
      await pumpFrames(tester);
      expect(map.fittedCoordinates, hasLength(1));
      map.onFit = null;
      await tester.tap(find.text('Réessayer'));
      await pumpFrames(tester);
      expect(map.cameras, hasLength(2));
      expect(map.fittedCoordinates, hasLength(2));
    },
  );

  focusTestWidgets(
    'formulaire rempli : protège réellement le commentaire et la caméra',
    (tester) async {
      gps.initial.complete(focusPosition());
      await mount(tester);
      await tester.tap(find.byTooltip('Créer un signalement'));
      await pumpFrames(tester);
      expect(find.byType(ReportComposerSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Brouillon à conserver');
      await pumpFrames(tester);
      expect(focus.isBlocked, true);
      expect(
        () => focus.focusAlert(focusReport()),
        throwsA(isA<MapFocusBlocked>()),
      );
      expect(find.text('Brouillon à conserver'), findsOneWidget);
      expect(find.byType(ReportComposerSheet), findsOneWidget);
      expect(map.cameras, isEmpty);
    },
  );

  test(
    'brouillon : bloque la sélection et libère l’attente sans perte',
    () async {
      final focus = MapFocusController();
      addTearDown(focus.dispose);
      focus.setBlocked(true);
      var unblocked = false;
      final waiting = focus.whenUnblocked.then((_) => unblocked = true);
      expect(focus.focus(focusReport()), false);
      expect(
        () => focus.focusAlert(focusReport()),
        throwsA(isA<MapFocusBlocked>()),
      );
      expect(focus.report, isNull);
      expect(unblocked, false);
      focus.setBlocked(false);
      await waiting;
      expect(unblocked, true);
    },
  );
}
