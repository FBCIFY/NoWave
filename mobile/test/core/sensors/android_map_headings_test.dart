import 'dart:async';
import 'dart:math' as math;

import 'package:blueway/core/sensors/android_map_headings.dart';
import 'package:blueway/core/sensors/android_rotation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precise_compass/precise_compass.dart';

AndroidRotationSample _flat(double heading) {
  final a = heading * math.pi / 180;
  return AndroidRotationSample([
    math.cos(a),
    math.sin(a),
    0,
    -math.sin(a),
    math.cos(a),
    0,
    0,
    0,
    1,
  ]);
}

CompassReading _reading({double magnetic = 10, double? trueNorth = 13}) =>
    CompassReading.unavailable().copyWith(
      headingMagnetic: magnetic,
      headingTrue: trueNorth,
      heading: trueNorth ?? magnetic,
      source: HeadingSource.rotationVector,
    );

void main() {
  late StreamController<CompassReading> compass;
  late StreamController<AndroidRotationSample> rotations;
  setUp(() {
    compass = StreamController.broadcast();
    rotations = StreamController.broadcast();
  });
  tearDown(() async {
    await compass.close();
    await rotations.close();
  });

  test('applique la déclinaison une seule fois, même autour de 0°', () async {
    final received = <double>[];
    final sub = AndroidMapHeadings(
      compass.stream,
      rotations.stream,
      smoothingFactor: 1,
    ).headings.listen(received.add);
    compass.add(_reading());
    await pumpEventQueue();
    rotations.add(_flat(358));
    await pumpEventQueue();
    expect(received.last, closeTo(1, 1e-9));
    compass.add(_reading(magnetic: 1, trueNorth: 358));
    await pumpEventQueue();
    expect(received.last, closeTo(355, 1e-9));
    await sub.cancel();
  });

  test('cap magnétique si le cap vrai est absent ou non fini', () async {
    final received = <double>[];
    final sub = AndroidMapHeadings(
      compass.stream,
      rotations.stream,
    ).headings.listen(received.add);
    compass.add(_reading(trueNorth: null));
    rotations.add(_flat(90));
    await pumpEventQueue();
    expect(received.last, closeTo(90, 1e-9));
    compass.add(_reading(trueNorth: double.nan));
    await pumpEventQueue();
    expect(received.last, closeTo(90, 1e-9));
    await sub.cancel();
  });

  test('lissage 359→0 et 0→359 sans passage par le sud', () async {
    for (final pair in [(359.0, 0.0, 359.12), (0.0, 359.0, 359.88)]) {
      final received = <double>[];
      final sub = AndroidMapHeadings(
        compass.stream,
        rotations.stream,
      ).headings.listen(received.add);
      rotations.add(_flat(pair.$1));
      await pumpEventQueue();
      rotations.add(_flat(pair.$2));
      await pumpEventQueue();
      expect(received.last > 358 || received.last < 1, isTrue);
      expect(received.last, closeTo(pair.$3, 1e-9));
      await sub.cancel();
    }
  });

  test('repli plugin si le canal matrice est indisponible', () async {
    final received = <double>[];
    final sub = AndroidMapHeadings(
      compass.stream,
      rotations.stream,
    ).headings.listen(received.add);
    rotations.addError(StateError('unavailable'));
    await pumpEventQueue();
    compass.add(_reading());
    await pumpEventQueue();
    expect(received.last, 13);
    await sub.cancel();
  });

  test(
    'plusieurs abonnés partagent les sources puis les libèrent et rouvrent',
    () async {
      final headings = AndroidMapHeadings(
        compass.stream,
        rotations.stream,
      ).headings;
      final first = headings.listen((_) {});
      final second = headings.listen((_) {});
      await first.cancel();
      expect(compass.hasListener, isTrue);
      expect(rotations.hasListener, isTrue);
      await second.cancel();
      expect(compass.hasListener, isFalse);
      expect(rotations.hasListener, isFalse);
      final received = <double>[];
      final third = headings.listen(received.add);
      rotations.add(_flat(180));
      await pumpEventQueue();
      expect(received.last, closeTo(180, 1e-9));
      await third.cancel();
    },
  );
}
