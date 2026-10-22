import 'dart:async';

import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../support/focus_fakes.dart';

class _Headings extends DeviceOrientationService {
  final values = StreamController<double>.broadcast(sync: true);
  @override
  Stream<double> get mapHeadings => values.stream;
}

class _Map extends FocusMap {
  double maxPitch = 80;
  int boundsRequests = 0;
  Future<mb.CameraBounds> Function()? onBounds;

  mb.CameraBounds get bounds => mb.CameraBounds(
    bounds: mb.CoordinateBounds(
      southwest: mb.Point(coordinates: mb.Position(-180, -85)),
      northeast: mb.Point(coordinates: mb.Position(180, 85)),
      infiniteBounds: true,
    ),
    minZoom: 0,
    maxZoom: 22,
    minPitch: 0,
    maxPitch: maxPitch,
  );

  @override
  Future<mb.CameraBounds> getBounds() async {
    boundsRequests++;
    return onBounds == null ? bounds : await onBounds!();
  }
}

void main() {
  late FocusGps gps;
  late _Headings headings;
  late _Map map;
  late MapFocusController focus;

  void navigationTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      gps = FocusGps()..onCurrent = () async => focusPosition();
      headings = _Headings();
      map = _Map();
      focus = MapFocusController();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await gps.close();
        await headings.values.close();
        focus.dispose();
      }
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  }

  mb.MapWidget widget(WidgetTester tester) =>
      tester.widget<mb.MapWidget>(find.byType(mb.MapWidget));

  mb.FollowPuckViewportState viewport(WidgetTester tester) =>
      widget(tester).viewport as mb.FollowPuckViewportState;

  // En mode cap, le natif laisse le cap à la caméra de cap : c'est le
  // dernier cap envoyé à la carte qui compte.
  double bearing(WidgetTester tester) => switch (viewport(tester).bearing) {
    mb.FollowPuckViewportStateBearingConstant(:final bearing) => bearing,
    _ =>
      map.cameras
          .lastWhere((camera) => camera.bearing != null)
          .bearing!
          .toDouble(),
  };

  Future<void> mount(WidgetTester tester, {bool reduceMotion = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: MapScreen(
          locationService: gps,
          orientationService: headings,
          focusController: focus,
        ),
      ),
    );
    widget(tester).onMapCreated!(map);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip(action));
    await tester.pumpAndSettle();
  }

  mb.MapContentGestureContext getGesture() => mb.MapContentGestureContext(
    point: mb.Point(coordinates: mb.Position(5.37, 43.29)),
    touchPosition: mb.ScreenCoordinate(x: 100, y: 100),
    gestureState: mb.GestureState.changed,
  );

  void cameraBearing(WidgetTester tester, double bearing) =>
      widget(tester).onCameraChangeListener!(
        mb.CameraChangedEventData.fromJson({
          'timestamp': 0,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [5.37, 43.29],
            },
            'zoom': 14.0,
            'pitch': 0.0,
            'bearing': bearing,
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
          },
        }),
      );

  navigationTest(
    'le nord rouge reste visible en carte libre et pendant le GPS',
    (tester) async {
      await mount(tester);
      final north = find.byKey(const ValueKey('navigation-north-marker'));
      expect(north, findsOneWidget);
      expect(
        tester.widget<Text>(find.text('N')).style!.color,
        const Color(0xFFBF5360),
      );
      headings.values.add(120);
      await press(tester, 'Recentrer sur ma position');
      await press(tester, 'Suivre la direction du téléphone');
      widget(tester).onScrollListener!(getGesture());
      cameraBearing(tester, 120);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Recentrer sur ma position'), findsOneWidget);
      expect(north, findsOneWidget);
      final center = tester.getCenter(
        find.byKey(const ValueKey('navigation-center-glyph')),
      );
      expect(tester.getCenter(north).dx, lessThan(center.dx));
      expect(tester.getCenter(north).dy, greaterThan(center.dy));

      final pending = Completer<geo.Position>();
      gps.onCurrent = () => pending.future;
      await tester.tap(find.byTooltip('Recentrer sur ma position'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(north, findsOneWidget);
      pending.complete(focusPosition());
      await tester.pumpAndSettle();
      expect(north, findsOneWidget);
    },
  );

  navigationTest('le nord reste droit et ne chevauche jamais la cible', (
    tester,
  ) async {
    await mount(tester);
    final north = find.byKey(const ValueKey('navigation-north-marker'));
    final center = find.byKey(const ValueKey('navigation-center-glyph'));
    final button = find.byTooltip('Recentrer sur ma position');
    for (var bearing = 0; bearing < 360; bearing += 15) {
      cameraBearing(tester, bearing.toDouble());
      await tester.pumpAndSettle();
      final marker = tester.getRect(north);
      expect(
        marker.overlaps(tester.getRect(center)),
        isFalse,
        reason: 'chevauchement au cap $bearing',
      );
      expect(tester.getRect(button).contains(marker.topLeft), isTrue);
      expect(tester.getRect(button).contains(marker.bottomRight), isTrue);
      final transform = tester.renderObject(north).getTransformTo(null);
      expect(transform.storage[1], closeTo(0, 0.0001));
      expect(transform.storage[4], closeTo(0, 0.0001));
    }
  });

  navigationTest('un seul bouton : nord à plat, direction à 75 %, puis nord', (
    tester,
  ) async {
    await mount(tester);
    expect(viewport(tester).pitch, 60); // Cadrage initial préservé.
    expect(find.byTooltip('Aligner la carte sur le cap actuel'), findsNothing);
    expect(find.byTooltip('Orienter la carte vers le nord'), findsNothing);
    await press(tester, 'Recentrer sur ma position');
    expect(viewport(tester).zoom, 12);
    expect(viewport(tester).padding!.top, 0);
    expect(viewport(tester).pitch, 0);
    expect(bearing(tester), 0);
    expect(find.text('N'), findsOneWidget);
    expect(find.textContaining('3D'), findsNothing);
    expect(find.byIcon(Icons.gps_fixed), findsOneWidget);
    final button = find.byTooltip('Suivre la direction du téléphone');
    expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final buttonBounds = tester.getRect(button);
    expect(buttonBounds.right, closeTo(screen.width - 16, 0.1));
    expect(buttonBounds.bottom, closeTo(screen.height - 260, 0.1));
    expect(
      buttonBounds.overlaps(
        tester.getRect(find.byTooltip('Créer un signalement')),
      ),
      isFalse,
    );

    headings.values.add(123);
    await tester.pumpAndSettle();
    expect(bearing(tester), 0); // Le nord reste fixe avant le deuxième appui.
    gps.positions.add(focusPosition(latitude: 43.30));
    await tester.pumpAndSettle();
    await press(tester, 'Suivre la direction du téléphone');
    expect(viewport(tester).zoom, 12);
    expect(viewport(tester).pitch, 60);
    final lookAhead = viewport(tester).padding!.top;
    expect(lookAhead, closeTo(screen.height * 0.24, 0.1));
    expect(viewport(tester).padding!.bottom, 0);
    expect(bearing(tester), 123);
    expect(find.byIcon(Icons.navigation), findsOneWidget);
    expect(find.byIcon(Icons.gps_fixed), findsNothing);

    headings.values.add(210);
    await tester.pumpAndSettle();
    expect(bearing(tester), 210);
    expect(viewport(tester).pitch, 60);
    expect(viewport(tester).padding!.top, lookAhead);
    gps.positions.add(focusPosition(latitude: 43.31));
    await tester.pumpAndSettle();
    expect(viewport(tester).padding!.top, lookAhead);
    await press(tester, 'Revenir au nord vrai à plat');
    expect(bearing(tester), 0);
    expect(viewport(tester).pitch, 0);
    expect(viewport(tester).padding!.top, 0);
    headings.values.add(270);
    await tester.pumpAndSettle();
    expect(bearing(tester), 0);
  });

  navigationTest('le contrôleur vide ne coupe pas le premier GPS tardif', (
    tester,
  ) async {
    final pending = Completer<geo.Position>();
    gps.onCurrent = () => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          locationService: gps,
          orientationService: headings,
          focusController: focus,
        ),
      ),
    );
    widget(tester).onMapCreated!(map);
    // Le premier callback du contrôleur arrive avant le premier fix GPS.
    await tester.pump();
    pending.complete(focusPosition());
    await tester.pumpAndSettle();
    expect(viewport(tester).zoom, 14);
    expect(viewport(tester).pitch, 60);
    await press(tester, 'Recentrer sur ma position');
    expect(viewport(tester).pitch, 0);
  });

  navigationTest('le cap tourne la carte en douceur, sans saut', (
    tester,
  ) async {
    await mount(tester);
    headings.values.add(60);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    final following = viewport(tester);
    expect(following.bearing, isNull);
    expect(bearing(tester), 60);

    map.cameras.clear();
    headings.values.add(120);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final turns = [
      for (final camera in map.cameras) camera.bearing!.toDouble(),
    ];
    expect(turns.length, greaterThan(3));
    for (var i = 1; i < turns.length; i++) {
      expect(turns[i], greaterThanOrEqualTo(turns[i - 1]));
      // Aucun pas visible d'une image à l'autre.
      expect(turns[i] - turns[i - 1], lessThan(10));
    }
    expect(turns.last, inExclusiveRange(60, 120));
    await tester.pumpAndSettle();
    expect(bearing(tester), 120);
    // Le suivi natif n'est pas recréé à chaque mesure.
    expect(viewport(tester), same(following));
  });

  for (final maxPitch in [60.0, 85.0]) {
    navigationTest('inclinaison calculée sur le maximum natif $maxPitch', (
      tester,
    ) async {
      map.maxPitch = maxPitch;
      await mount(tester);
      headings.values.add(45);
      await press(tester, 'Recentrer sur ma position');
      await press(tester, 'Suivre la direction du téléphone');
      expect(viewport(tester).pitch, maxPitch * 0.75);
    });
  }

  navigationTest('deuxième appui pendant le recentrage depuis le globe', (
    tester,
  ) async {
    map.maxPitch = 0; // La contrainte native du globe est encore en place.
    await mount(tester);
    headings.values.add(90);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    expect(viewport(tester).pitch, 85 * .75);
    expect(bearing(tester), 90);
    expect(find.byTooltip('Revenir au nord vrai à plat'), findsOneWidget);
  });

  navigationTest(
    'le GPS pendant l’appui sur le bouton ne réinitialise pas le cycle',
    (tester) async {
      await mount(tester);
      headings.values.add(90);
      await press(tester, 'Recentrer sur ma position');
      final touch = await tester.startGesture(
        tester.getCenter(find.byTooltip('Suivre la direction du téléphone')),
      );
      widget(tester).onCameraChangeListener!(
        mb.CameraChangedEventData.fromJson({
          'timestamp': 0,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [5.37, 43.29],
            },
            'zoom': 14.0,
            'pitch': 0.0,
            'bearing': 0.0,
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
          },
        }),
      );
      await tester.pump();
      expect(widget(tester).viewport, isA<mb.FollowPuckViewportState>());
      await touch.up();
      await tester.pumpAndSettle();
      expect(viewport(tester).pitch, 60);
      expect(bearing(tester), 90);
      expect(find.byTooltip('Revenir au nord vrai à plat'), findsOneWidget);
    },
  );

  navigationTest(
    'le repère nord et la flèche passent le nord sans tour complet',
    (tester) async {
      await mount(tester);
      headings.values.add(359);
      await press(tester, 'Recentrer sur ma position');
      await press(tester, 'Suivre la direction du téléphone');
      void camera(double value) => widget(tester).onCameraChangeListener!(
        mb.CameraChangedEventData.fromJson({
          'timestamp': 0,
          'cameraState': {
            'center': {
              'type': 'Point',
              'coordinates': [5.37, 43.29],
            },
            'zoom': 14.0,
            'pitch': 60.0,
            'bearing': value,
            'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
          },
        }),
      );
      camera(359);
      await tester.pumpAndSettle();
      final before = tester
          .widgetList<AnimatedRotation>(find.byType(AnimatedRotation))
          .map((rotation) => rotation.turns)
          .toList();
      headings.values.add(1);
      camera(1);
      await tester.pumpAndSettle();
      final after = tester
          .widgetList<AnimatedRotation>(find.byType(AnimatedRotation))
          .map((rotation) => rotation.turns)
          .toList();
      expect(bearing(tester), 1);
      expect(after.first - before.first, closeTo(-2 / 360, 0.0001));
      expect(after.last - before.last, closeTo(0, 0.0001));
    },
  );

  for (final zoomGesture in [false, true]) {
    navigationTest(
      'un geste ${zoomGesture ? 'zoom' : 'déplacement'} remet le cycle à zéro',
      (tester) async {
        await mount(tester);
        headings.values.add(60);
        await press(tester, 'Recentrer sur ma position');
        await press(tester, 'Suivre la direction du téléphone');
        (zoomGesture
            ? widget(tester).onZoomListener
            : widget(tester).onScrollListener)!(getGesture());
        await tester.pumpAndSettle();
        expect(widget(tester).viewport, isA<mb.IdleViewportState>());
        headings.values.add(90);
        await tester.pumpAndSettle();
        expect(widget(tester).viewport, isA<mb.IdleViewportState>());
        await press(tester, 'Recentrer sur ma position');
        expect(viewport(tester).pitch, 0);
        expect(bearing(tester), 0);
      },
    );
  }

  navigationTest('un cadrage de signalement réinitialise le bouton', (
    tester,
  ) async {
    await mount(tester);
    headings.values.add(60);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    focus.focus(focusReport());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Recentrer sur ma position'), findsOneWidget);
    expect(widget(tester).viewport, isA<mb.IdleViewportState>());
  });

  navigationTest('une rotation manuelle garde la priorité sur le capteur', (
    tester,
  ) async {
    await mount(tester);
    headings.values.add(60);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(mb.MapWidget)),
    );
    headings.values.add(90);
    await tester.pump();
    expect(bearing(tester), 60);
    widget(tester).onCameraChangeListener!(
      mb.CameraChangedEventData.fromJson({
        'timestamp': 0,
        'cameraState': {
          'center': {
            'type': 'Point',
            'coordinates': [5.37, 43.29],
          },
          'zoom': 14.0,
          'pitch': 60.0,
          'bearing': 120.0,
          'padding': {'top': 0.0, 'left': 0.0, 'bottom': 0.0, 'right': 0.0},
        },
      }),
    );
    await gesture.up();
    headings.values.add(150);
    await tester.pumpAndSettle();
    expect(widget(tester).viewport, isA<mb.IdleViewportState>());
    await press(tester, 'Recentrer sur ma position');
    expect(viewport(tester).pitch, 0);
    expect(bearing(tester), 0);
  });

  navigationTest('cap absent ou perdu : conserver le dernier état valide', (
    tester,
  ) async {
    await mount(tester);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    expect(find.text('Cap du téléphone indisponible.'), findsOneWidget);
    expect(viewport(tester).pitch, 0);
    expect(map.boundsRequests, 0);
    headings.values.add(45);
    await press(tester, 'Suivre la direction du téléphone');
    final lastValid = viewport(tester);
    headings.values.add(double.nan);
    headings.values.addError(StateError('Cap perdu'));
    await tester.pumpAndSettle();
    expect(viewport(tester), same(lastValid));
    headings.values.add(90);
    await tester.pumpAndSettle();
    expect(bearing(tester), 90);
  });

  navigationTest('erreur GPS : conserver le suivi de direction précédent', (
    tester,
  ) async {
    await mount(tester);
    headings.values.add(45);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    gps.onCurrent = () => Future.error(TimeoutException('GPS'));
    await press(tester, 'Revenir au nord vrai à plat');
    expect(viewport(tester).pitch, 60);
    expect(bearing(tester), 45);
    expect(find.byTooltip('Revenir au nord vrai à plat'), findsOneWidget);
    expect(
      find.text('Position introuvable pour le moment. Réessayez.'),
      findsWidgets,
    );
  });

  navigationTest(
    'erreur Mapbox : conserver le nord et permettre un nouvel essai',
    (tester) async {
      await mount(tester);
      headings.values.add(45);
      await press(tester, 'Recentrer sur ma position');
      map.onBounds = () => Future.error(StateError('Mapbox indisponible'));
      await press(tester, 'Suivre la direction du téléphone');
      expect(viewport(tester).pitch, 0);
      expect(find.text('Impossible de changer l’orientation.'), findsOneWidget);
      map.onBounds = null;
      await press(tester, 'Suivre la direction du téléphone');
      expect(viewport(tester).pitch, 60);
    },
  );

  navigationTest('appuis rapides et geste pendant une demande GPS', (
    tester,
  ) async {
    await mount(tester);
    final pending = Completer<geo.Position>();
    var requests = 0;
    gps.onCurrent = () {
      requests++;
      return pending.future;
    };
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (value) =>
            value is IconButton && value.tooltip == 'Recentrer sur ma position',
      ),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(requests, 1);
    widget(tester).onScrollListener!(getGesture());
    pending.complete(focusPosition());
    await tester.pumpAndSettle();
    expect(widget(tester).viewport, isA<mb.IdleViewportState>());
    expect(find.byTooltip('Recentrer sur ma position'), findsOneWidget);
  });

  navigationTest(
    'geste pendant la lecture des limites : pas de reprise tardive',
    (tester) async {
      await mount(tester);
      headings.values.add(60);
      await press(tester, 'Recentrer sur ma position');
      final pending = Completer<mb.CameraBounds>();
      map.onBounds = () => pending.future;
      await tester.tap(find.byTooltip('Suivre la direction du téléphone'));
      await tester.pump();
      widget(tester).onZoomListener!(getGesture());
      pending.complete(map.bounds);
      await tester.pumpAndSettle();
      expect(widget(tester).viewport, isA<mb.IdleViewportState>());
      await press(tester, 'Recentrer sur ma position');
      expect(viewport(tester).pitch, 0);
    },
  );

  navigationTest('le formulaire masque le bouton et restaure le suivi du cap', (
    tester,
  ) async {
    await prepareFocusMarkers(tester);
    await mount(tester);
    headings.values.add(60);
    await press(tester, 'Recentrer sur ma position');
    await press(tester, 'Suivre la direction du téléphone');
    map.cameraPitch = 60;
    map.cameraBearing = 60;
    final lookAhead = viewport(tester).padding!.top;
    await press(tester, 'Créer un signalement');
    expect(find.byTooltip('Revenir au nord vrai à plat'), findsNothing);
    headings.values.add(120);
    await tester.pumpAndSettle();
    expect(widget(tester).viewport, isA<mb.CameraViewportState>());
    await press(tester, 'Fermer');
    expect(viewport(tester).pitch, 60);
    expect(bearing(tester), 120);
    expect(viewport(tester).padding!.top, lookAhead);
    headings.values.add(180);
    await tester.pumpAndSettle();
    expect(bearing(tester), 180);
  });

  navigationTest('réduction des animations et état accessible explicite', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, reduceMotion: true);
      headings.values.add(60);
      await press(tester, 'Recentrer sur ma position');
      expect(
        find.bySemanticsLabel(RegExp('Centré sur ma position, nord vrai')),
        findsWidgets,
      );
      await press(tester, 'Suivre la direction du téléphone');
      expect(
        find.bySemanticsLabel(RegExp('Centré sur ma position, direction')),
        findsWidgets,
      );
      for (final rotation in tester.widgetList<AnimatedRotation>(
        find.byType(AnimatedRotation),
      )) {
        expect(rotation.duration, Duration.zero);
      }
      expect(viewport(tester).pitch, 60);
      expect(map.animationDurations, isEmpty);
    } finally {
      semantics.dispose();
    }
  });
}
