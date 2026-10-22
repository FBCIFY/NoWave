import 'dart:async';

import 'package:blueway/core/map/heading_camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late _Clock clock;
  late List<double> sent;
  late bool active;
  late HeadingCamera camera;

  setUp(() {
    sent = [];
    active = true;
    camera = HeadingCamera(
      rotate: (bearing) async => sent.add(bearing),
      active: () => active,
      createTicker: (frame) => clock = _Clock(frame),
    );
  });

  tearDown(() => camera.dispose());

  Future<void> run(int from, int to) async {
    for (var ms = from; ms <= to; ms += 16) {
      await clock.at(ms);
    }
  }

  test('rejoint le cap par petits pas, puis s’arrête pile dessus', () async {
    camera.aim(90, from: 0);
    await run(0, 2000);
    expect(sent.last, 90);
    expect(clock.active, isFalse);
    for (var i = 1; i < sent.length; i++) {
      expect(sent[i], greaterThanOrEqualTo(sent[i - 1]));
      expect(sent[i] - sent[i - 1], lessThan(10));
    }
  });

  test('passe le nord par le plus court chemin', () async {
    camera.aim(10, from: 350);
    await run(0, 2000);
    expect(sent.last, 10);
    for (final bearing in sent) {
      expect(bearing < 11 || bearing >= 350, isTrue, reason: '$bearing');
    }
  });

  test('une nouvelle mesure en route garde l’élan, sans repartir', () async {
    camera.aim(90, from: 0);
    await run(0, 96);
    final reached = sent.last;
    camera.aim(100, from: 0); // Événement caméra en retard : ignoré.
    await run(112, 128);
    expect(sent.last, greaterThan(reached));
    await run(144, 2000);
    expect(sent.last, 100);
  });

  test(
    'une seule commande à la fois : un natif lent saute des images',
    () async {
      final pending = Completer<void>();
      var calls = 0;
      final slow = HeadingCamera(
        rotate: (_) {
          calls++;
          return pending.future;
        },
        active: () => true,
        createTicker: (frame) => clock = _Clock(frame),
      );
      slow.aim(90, from: 0);
      await run(16, 200);
      expect(calls, 1);
      pending.complete();
      slow.dispose();
    },
  );

  test('s’arrête quand le suivi du cap n’est plus actif', () async {
    camera.aim(90, from: 0);
    await run(0, 48);
    active = false;
    final count = sent.length;
    await run(64, 200);
    expect(sent.length, count);
    expect(clock.active, isFalse);
  });

  test('réduction des animations : directement au cap', () async {
    camera.aim(270, from: 0, reduceMotion: true);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [270]);
    expect(clock.active, isFalse);
  });

  test(
    'réduction des animations : une commande à la fois, puis le dernier cap',
    () async {
      final pending = Completer<void>();
      final jumps = <double>[];
      final slow = HeadingCamera(
        rotate: (bearing) {
          jumps.add(bearing);
          return jumps.length == 1 ? pending.future : Future.value();
        },
        active: () => active,
        createTicker: (frame) => _Clock(frame),
      );
      addTearDown(slow.dispose);
      slow.aim(10, from: 0, reduceMotion: true);
      slow.aim(20, from: 0, reduceMotion: true);
      slow.aim(30, from: 0, reduceMotion: true);
      await Future<void>.delayed(Duration.zero);
      expect(jumps, [10]);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      // Les caps intermédiaires sont sautés : seul le dernier compte.
      expect(jumps, [10, 30]);
    },
  );

  test(
    'réduction des animations : un toucher annule le cap en attente',
    () async {
      final pending = Completer<void>();
      final jumps = <double>[];
      final slow = HeadingCamera(
        rotate: (bearing) {
          jumps.add(bearing);
          return pending.future;
        },
        active: () => active,
        createTicker: (frame) => _Clock(frame),
      );
      addTearDown(slow.dispose);
      slow.aim(10, from: 0, reduceMotion: true);
      slow.aim(20, from: 0, reduceMotion: true);
      slow.stop();
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(jumps, [10]);
    },
  );

  test('pas d’un pas : lissage exponentiel', () {
    final half = HeadingCamera.smoothing * 0.6931471805599453;
    expect(HeadingCamera.step(0, 100, half), closeTo(50, 1e-3));
    expect(HeadingCamera.step(0, 100, Duration.zero), 0);
    expect(HeadingCamera.step(89.99, 90, const Duration(milliseconds: 16)), 90);
  });
}
