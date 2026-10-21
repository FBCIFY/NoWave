import 'dart:async';
import 'dart:math' as math;

import 'package:blueway/core/map/globe_rotation_controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Clock extends Ticker {
  _Clock(this.frame) : super(frame);
  final TickerCallback frame;
  bool active = false;
  bool disposed = false;
  @override
  bool get isActive => active;
  @override
  TickerFuture start() {
    active = true;
    return TickerFuture.complete();
  }

  @override
  void stop({bool canceled = false}) => active = false;
  @override
  void dispose() {
    active = false;
    disposed = true;
    super.dispose();
  }

  Future<void> at(int milliseconds) async {
    if (active) frame(Duration(milliseconds: milliseconds));
    await Future<void>.delayed(Duration.zero);
  }
}

CameraState camera({double zoom = .65, double longitude = 15}) => CameraState(
  center: Point(coordinates: Position(longitude, 12)),
  zoom: zoom,
  bearing: 0,
  pitch: 0,
  padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
);

void main() {
  late _Clock clock;
  late GlobeRotationController rotation;
  late List<CameraOptions> moves;
  setUp(() {
    moves = [];
    rotation = GlobeRotationController(
      moveCamera: (camera) async => moves.add(camera),
      createTicker: (callback) => clock = _Clock(callback),
    );
  });
  tearDown(() => rotation.dispose());
  void ready({
    bool visible = true,
    bool reduceMotion = false,
    bool ready = true,
  }) {
    rotation.configure(
      ready: ready,
      visible: visible,
      reduceMotion: reduceMotion,
    );
  }

  test('aucune rotation au démarrage ; activation explicite sans modifier le cadrage', () async {
    ready();
    expect(rotation.isRotating, false);
    rotation.cameraChanged(camera());
    expect(rotation.isRotating, false);
    await clock.at(1000);
    expect(moves, isEmpty);
    rotation.resumeWhenIdle();
    expect(rotation.isRotating, true);
    await clock.at(1000);
    expect(moves.single.center!.coordinates.lng, 17);
    expect(moves.single.center!.coordinates.lat, 12);
    expect(moves.single.zoom, isNull);
    expect(moves.single.bearing, isNull);
    expect(moves.single.pitch, isNull);
    expect(moves.single.padding, isNull);
    expect(moves.single.anchor, isNull);
  });

  test(
    'écran 120 Hz : au plus 31 commandes par seconde à vitesse inchangée',
    () async {
      rotation.cameraChanged(camera());
      ready();
      rotation.resumeWhenIdle();
      for (var frame = 0; frame <= 120; frame++) {
        await clock.at(frame * 1000 ~/ 120);
      }
      expect(moves.length, lessThanOrEqualTo(31));
      expect(moves.last.center!.coordinates.lng, closeTo(17, 1e-9));
    },
  );

  test(
    'Z0 et Z4.5 inclus, arrêt hors plage sans commande ni retour de zoom',
    () async {
      ready();
      var elapsed = 0;
      for (final zoom in [
        0.0,
        .65,
        .7,
        2.0,
        4.5,
        4.500001,
        6.0,
        -0.01,
        double.nan,
      ]) {
        rotation.cameraChanged(camera(zoom: zoom));
        rotation.resumeWhenIdle();
        final count = moves.length;
        await clock.at(elapsed += 1000);
        final allowed = zoom.isFinite && zoom >= 0 && zoom <= 4.5;
        expect(rotation.isRotating, allowed, reason: '$zoom');
        expect(moves.length, count + (allowed ? 1 : 0));
      }
    },
  );

  test(
    '2°/s uniformes, tour complet et antiméridien sans saut angulaire',
    () async {
      rotation.cameraChanged(camera(longitude: 179));
      ready();
      rotation.resumeWhenIdle();
      var previous = 179.0;
      for (var milliseconds = 0; milliseconds <= 180000; milliseconds += 500) {
        await clock.at(milliseconds);
        final longitude = moves.last.center!.coordinates.lng.toDouble();
        expect(longitude, greaterThanOrEqualTo(-180));
        expect(longitude, lessThan(180));
        final delta = GlobeRotationController.normalizeLongitude(
          longitude - previous,
        );
        expect(delta, closeTo(milliseconds == 0 ? 0 : 1, 1e-9));
        previous = longitude;
      }
      expect(moves[2].center!.coordinates.lng, -179);
      expect(previous, closeTo(179, 1e-9));
      await clock.at(180500);
      expect(moves.last.center!.coordinates.lng, -180);
    },
  );

  test('longitude croissante déplace un continent vers la gauche en projection globe', () async {
    rotation.cameraChanged(camera(longitude: 0));
    ready();
    rotation.resumeWhenIdle();
    await clock.at(1000);
    // Orthographic geometry only; does not validate native Android rendering.
    double screenX(double center) => math.sin((20 - center) * math.pi / 180);
    expect(
      screenX(moves.single.center!.coordinates.lng.toDouble()),
      lessThan(screenX(0)),
    );
  });

  test(
    'suspension, reprise sans temps caché, reload et réduction des animations',
    () async {
      rotation.cameraChanged(camera());
      ready();
      rotation.resumeWhenIdle();
      await clock.at(1000);
      rotation.cameraChanged(camera(longitude: 17));
      ready(visible: false);
      await clock.at(80000);
      expect(moves, hasLength(1));
      ready();
      await clock.at(500);
      expect(moves.last.center!.coordinates.lng, 18);
      for (final condition in ['style', 'motion']) {
        ready(ready: condition != 'style', reduceMotion: condition == 'motion');
        expect(rotation.isRotating, false);
        final count = moves.length;
        await clock.at(10000);
        expect(moves.length, count);
        ready();
        expect(rotation.isRotating, true);
      }
    },
  );

  test(
    'geste arrête ; relâchement réactive depuis la nouvelle caméra',
    () async {
      rotation.cameraChanged(camera());
      ready();
      rotation.resumeWhenIdle();
      await clock.at(500);
      await rotation.stopForInteraction();
      expect(rotation.dismissed, true);
      ready(visible: false);
      ready();
      rotation.cameraChanged(camera(zoom: 2));
      rotation.cameraChanged(camera());
      ready(ready: false);
      ready();
      await clock.at(5000);
      expect(moves, hasLength(1));
      expect(rotation.isRotating, false);
      rotation.resumeWhenIdle();
      expect(rotation.isRotating, true);
      await clock.at(500);
      expect(moves, hasLength(2));
    },
  );

  test('reprise pendant une priorité ou animation réduite ne crée pas de reprise différée', () async {
    rotation.cameraChanged(camera());
    for (final condition in ['ready', 'visible', 'motion']) {
      ready(
        ready: condition != 'ready',
        visible: condition != 'visible',
        reduceMotion: condition == 'motion',
      );
      rotation.resumeWhenIdle();
      ready();
      await clock.at(1000);
      expect(rotation.isRotating, false);
      expect(moves, isEmpty);
    }
  });

  test(
    'aucun appel concurrent ni file de frames ; priorité attend l’appel envoyé',
    () async {
      final gate = Completer<void>();
      rotation.dispose();
      rotation = GlobeRotationController(
        moveCamera: (camera) {
          moves.add(camera);
          return gate.future;
        },
        createTicker: (callback) => clock = _Clock(callback),
      );
      rotation.cameraChanged(camera());
      ready();
      rotation.resumeWhenIdle();
      await clock.at(100);
      await clock.at(200);
      await clock.at(300);
      expect(moves, hasLength(1));
      var drained = false;
      final stop = rotation.stopForInteraction().then((_) => drained = true);
      expect(rotation.isRotating, false);
      expect(drained, false);
      gate.complete();
      await stop;
      expect(drained, true);
      await clock.at(400);
      expect(moves, hasLength(1));
    },
  );

  test('dispose avec appel en cours ne relance aucune ressource', () async {
    final gate = Completer<void>();
    rotation.dispose();
    rotation = GlobeRotationController(
      moveCamera: (_) => gate.future,
      createTicker: (callback) => clock = _Clock(callback),
    );
    rotation.cameraChanged(camera());
    ready();
    rotation.resumeWhenIdle();
    await clock.at(10);
    rotation.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    ready();
    rotation.cameraChanged(camera());
    expect(clock.disposed, true);
    expect(rotation.isRotating, false);
  });

  test(
    'erreur native synchrone ou asynchrone : arrêt sans boucle de retries',
    () async {
      for (final synchronous in [true, false]) {
        rotation.dispose();
        rotation = GlobeRotationController(
          moveCamera: (_) {
            if (synchronous) throw StateError('map unavailable');
            return Future<void>.error(StateError('map unavailable'));
          },
          createTicker: (callback) => clock = _Clock(callback),
        );
        rotation.cameraChanged(camera());
        ready();
        rotation.resumeWhenIdle();
        await clock.at(10);
        expect(rotation.isRotating, false);
        expect(rotation.dismissed, true);
      }
    },
  );
}
