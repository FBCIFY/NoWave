import 'dart:async';

import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:precise_compass/precise_compass.dart';

CompassReading _reading({double? headingTrue}) =>
    CompassReading.unavailable().copyWith(
      headingMagnetic: 90,
      headingTrue: headingTrue,
      heading: headingTrue ?? 90,
      source: HeadingSource.rotationVector,
    );

/// Faux plugin : compte les ouvertures et fermetures du flux natif.
class _FakeCompass {
  int opened = 0;
  int closed = 0;

  late final controller = StreamController<CompassReading>.broadcast(
    onListen: () => opened++,
    onCancel: () => closed++,
  );
}

void main() {
  late _FakeCompass compass;
  late DateTime now;

  setUp(() {
    compass = _FakeCompass();
    now = DateTime(2026, 10, 5, 17);
  });

  SharedCompassReadings shared({bool restartWithoutTrueNorth = true}) =>
      SharedCompassReadings(
        compass.controller.stream,
        restartWithoutTrueNorth: restartWithoutTrueNorth,
        now: () => now,
      );

  test('ouvre un seul flux natif pour tous les abonnés', () async {
    final readings = shared().readings;
    final first = readings.listen((_) {});
    final second = readings.listen((_) {});
    await pumpEventQueue();

    expect(compass.opened, 1);

    await first.cancel();
    await second.cancel();
    expect(compass.closed, 1);
  });

  test('rouvre le flux quand le cap vrai manque encore après 5 s', () async {
    final received = <CompassReading>[];
    final subscription = shared().readings.listen(received.add);
    await pumpEventQueue();

    compass.controller.add(_reading());
    await pumpEventQueue();
    expect(compass.opened, 1);

    now = now.add(const Duration(seconds: 6));
    compass.controller.add(_reading());
    await pumpEventQueue();

    expect(compass.closed, 1);
    expect(compass.opened, 2);

    // Rouvert, le flux continue d'arriver aux mêmes abonnés.
    compass.controller.add(_reading(headingTrue: 92));
    await pumpEventQueue();
    expect(received.last.headingTrue, 92);

    await subscription.cancel();
  });

  test('garde le flux quand le cap vrai est là', () async {
    final subscription = shared().readings.listen((_) {});
    await pumpEventQueue();

    now = now.add(const Duration(seconds: 6));
    compass.controller.add(_reading(headingTrue: 92));
    await pumpEventQueue();

    expect(compass.opened, 1);
    expect(compass.closed, 0);
    await subscription.cancel();
  });

  test('ne rouvre pas sans capteurs ni hors Android', () async {
    final subscription = shared(restartWithoutTrueNorth: false).readings
        .listen((_) {});
    await pumpEventQueue();

    now = now.add(const Duration(seconds: 6));
    compass.controller.add(_reading());
    await pumpEventQueue();
    expect(compass.opened, 1);
    await subscription.cancel();

    final other = _FakeCompass();
    compass = other;
    final unavailable = shared().readings.listen((_) {});
    await pumpEventQueue();
    now = now.add(const Duration(seconds: 6));
    other.controller.add(CompassReading.unavailable());
    await pumpEventQueue();
    expect(other.opened, 1);
    await unavailable.cancel();
  });
}
