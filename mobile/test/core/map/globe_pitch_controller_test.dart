import 'dart:async';

import 'package:blueway/core/map/globe_pitch_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

CameraState camera(double zoom, double pitch) => CameraState(
  center: Point(coordinates: Position(5.94, 43.08)),
  zoom: zoom,
  pitch: pitch,
  bearing: 25,
  padding: MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
);

class _Gestures extends Fake implements GesturesSettingsInterface {
  final enabled = <bool?>[];
  @override
  Future<void> updateSettings(GesturesSettings settings) async {
    enabled.add(settings.pitchEnabled);
  }
}

class _Map extends Fake implements MapboxMap {
  @override
  final _Gestures gestures = _Gestures();
  final bounds = <CameraBoundsOptions>[];
  final moves = <CameraOptions>[];
  Completer<void>? boundGate;
  void Function(CameraOptions)? onMove;
  @override
  Future<void> setBounds(CameraBoundsOptions value) async {
    bounds.add(value);
    await boundGate?.future;
  }

  @override
  Future<void> setCamera(CameraOptions value) async {
    moves.add(value);
    onMove?.call(value);
  }
}

void main() {
  late GlobePitchController controller;
  late _Map map;
  setUp(() {
    controller = GlobePitchController();
    map = _Map();
  });
  tearDown(() => controller.dispose());
  Future<void> sync(double zoom, double pitch, {bool editing = false}) =>
      controller.synchronize(map, camera(zoom, pitch), editing: editing);

  test(
    'transition réversible Z6 → Z4.5, pitch précédent restauré au retour',
    () async {
      await sync(7, 40);
      expect(map.moves, isEmpty);
      await sync(6, 40);
      await sync(5.25, 40);
      expect(map.moves.last.pitch, 20);
      await sync(4.5, 20);
      expect(map.moves.last.pitch, 0);
      expect(map.bounds.last.maxPitch, 0);
      expect(map.gestures.enabled.last, false);
      await sync(5.25, 0);
      expect(map.moves.last.pitch, 20);
      await sync(6, 20);
      expect(map.moves.last.pitch, 40);
      expect(map.bounds.last.maxPitch, 85);
      expect(map.gestures.enabled.last, true);
      for (final move in map.moves) {
        expect(move.center, isNull);
        expect(move.zoom, isNull);
        expect(move.bearing, isNull);
        expect(move.padding, isNull);
      }
    },
  );

  test(
    'borne native à 0 sous Z4.5, y compris après tentative de tilt',
    () async {
      for (final zoom in [4.5, 4.0, 2.0, .7, 0.0]) {
        await sync(zoom, 60);
        expect(map.moves.last.pitch, 0);
      }
      expect(map.bounds, hasLength(1));
      expect(map.bounds.single.minPitch, 0);
      expect(map.bounds.single.maxPitch, 0);
      expect(map.gestures.enabled, [false]);
    },
  );

  test('formulaire plat, sans perdre le pitch détaillé', () async {
    await sync(14, 50);
    await sync(14, 50, editing: true);
    await sync(14, 0, editing: true);
    expect(map.bounds.last.maxPitch, 0);
    await sync(14, 0);
    expect(map.moves.last.pitch, 50);
    expect(map.gestures.enabled.last, true);
  });

  test(
    'événements natifs de correction ne remplacent pas le pitch mémorisé',
    () async {
      await sync(8, 60);
      map.onMove = (move) {
        unawaited(sync(5.25, move.pitch!));
      };
      await sync(5.25, 60);
      expect(map.moves.last.pitch, 30);
      map.onMove = (move) {
        unawaited(sync(6, move.pitch!));
      };
      await sync(6, 30);
      expect(map.moves.last.pitch, 60);
    },
  );

  test('changement de zoom pendant un appel natif : aucune ancienne correction appliquée', () async {
    final gate = Completer<void>();
    map.boundGate = gate;
    final first = sync(4.5, 60);
    final latest = sync(8, 40);
    gate.complete();
    await Future.wait([first, latest]);
    expect(map.bounds.last.maxPitch, 85);
    expect(map.moves.last.pitch, 60);
    expect(map.moves.any((move) => move.pitch == 0), false);
  });

  test(
    'dispose pendant un appel natif : aucune commande caméra tardive',
    () async {
      final gate = Completer<void>();
      map.boundGate = gate;
      final pending = sync(4.5, 60);
      controller.dispose();
      gate.complete();
      await pending;
      expect(map.moves, isEmpty);
    },
  );
}
