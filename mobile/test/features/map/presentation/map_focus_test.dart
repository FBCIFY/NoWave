import 'dart:async';
import 'dart:convert';

import 'package:blueway/features/map/presentation/report_marker.dart' as badges;
import 'package:blueway/features/reports/domain/manual_report.dart';

import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:blueway/features/reports/presentation/report_detail_sheet.dart';
import 'package:blueway/features/reports/presentation/report_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../support/focus_fakes.dart';

class _Reports extends Fake implements ReportDetailService {
  final calls = <String>[];
  @override
  Future<ReportDetail> fetchReport(String id) async {
    calls.add(id);
    return focusReport(id: id);
  }
}

class _LateTiles extends Fake implements ReportTiles {
  final ready = Completer<void>();
  final pulseEnabled = <bool>[];
  int stops = 0;
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

  @override
  void stopPulse() => stops++;
  @override
  void updatePulse(
    mb.MapboxMap map, {
    required double zoom,
    required bool enabled,
  }) => pulseEnabled.add(enabled);
}

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
  }) async {
    await prepareFocusMarkers(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          focusController: focus,
          locationService: gps,
          reportDetailService: reports,
          reportTiles: tiles,
        ),
      ),
    );
    tester.widget<mb.MapWidget>(find.byType(mb.MapWidget)).onMapCreated!(map);
    if (style) styleReady(tester);
    await pumpFrames(tester);
  }

  focusTestWidgets(
    'une route au-dessus suspend les traitements visuels jusqu’au retour',
    (tester) async {
      const channel =
          'dev.flutter.pigeon.mapbox_maps_flutter._OfflineSwitch.setMapboxStackConnected';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
        channel,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      final tiles = _LateTiles()..ready.complete();
      gps.initial.complete(focusPosition());
      await mount(tester, tiles: tiles);
      expect(tiles.pulseEnabled, contains(true));
      final navigator = Navigator.of(tester.element(find.byType(MapScreen)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Profil')),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(tiles.stops, greaterThan(0));
      final updates = tiles.pulseEnabled.length;
      gps.positions.add(focusPosition(longitude: 7));
      await pumpFrames(tester);
      expect(tiles.pulseEnabled.length, updates);
      navigator.pop();
      await pumpFrames(tester);
      expect(tiles.pulseEnabled.length, greaterThan(updates));
      expect(tiles.pulseEnabled.last, isTrue);
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
      'alert-selected-point',
    ]);
    expect(map.style.sources.keys.where((id) => id.startsWith('alert-')), [
      'alert-selected',
    ]);
    expect(map.style.images.keys, [
      badges.ReportMarker.imageId(ReportCategory.marineAnimal),
    ]);
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
        'alert-selected-point',
      ]);
      expect(map.cameras, hasLength(1));
      focus.clear();
      await pumpFrames(tester);
      expect(map.style.layers, isNot(contains('alert-selected-point')));
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
      expect(map.location.settings.last.enabled, true);
      expect(map.location.settings.last.puckBearingEnabled, false);
      expect(
        map.location.settings.last.locationPuck!.locationPuck2D,
        isNotNull,
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
      final interaction = map.interactions.single;
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
      await pumpFrames(tester);
      expect(reports.calls, ['report-a']);
      expect(find.byType(ReportDetailSheet), findsOneWidget);
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
