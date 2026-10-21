import 'dart:async';

import 'package:blueway/core/map/globe_flight.dart';
import 'package:blueway/core/map/globe_pitch_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

class _Clock extends Ticker {
  _Clock(this.frame) : super(frame);
  final TickerCallback frame;
  bool active = false;
  @override
  bool get isActive => active;
  @override
  TickerFuture start() {
    active = true;
    return TickerFuture.complete();
  }

  @override
  void stop({bool canceled = false}) => active = false;

  Future<void> at(int milliseconds) async {
    if (active) frame(Duration(milliseconds: milliseconds));
    await Future<void>.delayed(Duration.zero);
  }
}

const _phone = Size(393, 852);

/// Globe au-dessus de l'Atlantique, arrivée à Marseille au niveau de la rue.
final _globeToMarseille = GlobeFlightPath(
  from: (longitude: -30, latitude: 20, zoom: 1.5, bearing: 0),
  to: (longitude: 5.37, latitude: 43.3, zoom: 14, bearing: 0),
  viewport: _phone,
);

void main() {
  test('part de la caméra et arrive pile sur l’utilisateur', () {
    expect(_globeToMarseille.at(0), _globeToMarseille.from);
    final end = _globeToMarseille.at(1);
    expect(end.longitude, closeTo(5.37, 1e-9));
    expect(end.latitude, 43.3);
    expect(end.zoom, 14);
  });

  test('traverse loin, puis plonge : à plat jusqu’aux nuages', () {
    double? crossing;
    var previousZoom = 1.5;
    for (var t = 0.0; t <= 1; t += .001) {
      final camera = _globeToMarseille.at(t);
      expect(camera.zoom, inInclusiveRange(1.5 - 1e-9, 14));
      expect(camera.zoom, greaterThanOrEqualTo(previousZoom - 1e-9));
      previousZoom = camera.zoom;
      if (crossing == null && camera.zoom > GlobePitchController.flatZoom) {
        crossing = t;
        // Les nuages passés, on est déjà au-dessus de la France : la
        // caméra s'incline en descendant, pas en traversant l'Atlantique.
        expect((camera.longitude - 5.37).abs(), lessThan(4));
        expect((camera.latitude - 43.3).abs(), lessThan(4));
      }
    }
    expect(crossing, isNotNull);
  });

  test('passe par l’antiméridien quand c’est plus court', () {
    final path = GlobeFlightPath(
      from: (longitude: 170, latitude: 0, zoom: 3, bearing: 350),
      to: (longitude: -170, latitude: 0, zoom: 3, bearing: 10),
      viewport: _phone,
    );
    final middle = path.at(.5);
    expect(middle.longitude.abs(), greaterThan(175));
    expect(middle.bearing % 360, closeTo(0, 1e-9));
    expect(path.at(1).longitude % 360, closeTo(190, 1e-9));
  });

  test('même centre : zoom seul', () {
    final path = GlobeFlightPath(
      from: (longitude: 5, latitude: 43, zoom: 2, bearing: 0),
      to: (longitude: 5, latitude: 43, zoom: 14, bearing: 0),
      viewport: _phone,
    );
    for (final t in [.25, .5, .75]) {
      final camera = path.at(t);
      expect(camera.longitude, closeTo(5, 1e-9));
      expect(camera.latitude, closeTo(43, 1e-9));
      expect(camera.zoom, closeTo(2 + 12 * t, 1e-9));
    }
  });

  group('lecture du vol', () {
    late _Clock clock;
    late GlobeFlight flight;
    final cameras = <CameraOptions>[];
    var interrupted = false;

    setUp(() {
      cameras.clear();
      interrupted = false;
      flight = GlobeFlight(createTicker: (frame) => clock = _Clock(frame));
    });
    tearDown(() => flight.dispose());

    Future<bool> fly() => flight.fly(
      path: _globeToMarseille,
      duration: const Duration(milliseconds: 1000),
      pitchAt: (zoom) => GlobePitchController.pitchAt(zoom, 60),
      moveCamera: (camera) async => cameras.add(camera),
      interrupted: () => interrupted,
    );

    test('inclinaison tirée du zoom, arrivée à 60°', () async {
      final done = fly();
      for (var ms = 0; ms <= 1000; ms += 100) {
        await clock.at(ms);
      }
      expect(await done, isTrue);
      expect(cameras, hasLength(11));
      for (final camera in cameras) {
        expect(
          camera.pitch,
          GlobePitchController.pitchAt(camera.zoom!.toDouble(), 60),
        );
      }
      expect(cameras.first.pitch, 0);
      expect(cameras.last.pitch, 60);
      expect(cameras.last.zoom, 14);
      expect(clock.active, isFalse);
    });

    test('un geste arrête le vol là où il est', () async {
      final done = fly();
      await clock.at(0);
      await clock.at(100);
      interrupted = true;
      await clock.at(200);
      expect(await done, isFalse);
      expect(cameras, hasLength(2));
      expect(clock.active, isFalse);
    });

    test(
      'une image à la fois : la plateforme lente saute des images',
      () async {
        final slow = Completer<void>();
        final done = flight.fly(
          path: _globeToMarseille,
          duration: const Duration(milliseconds: 1000),
          pitchAt: (_) => 0,
          moveCamera: (camera) {
            cameras.add(camera);
            return slow.future;
          },
          interrupted: () => false,
        );
        await clock.at(0);
        await clock.at(500);
        await clock.at(900);
        expect(cameras, hasLength(1));
        slow.complete();
        await Future<void>.delayed(Duration.zero);
        await clock.at(1000);
        expect(await done, isTrue);
        expect(cameras, hasLength(2));
      },
    );
  });
}
