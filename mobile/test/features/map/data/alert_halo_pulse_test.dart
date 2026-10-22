import 'dart:async';

import 'package:blueway/features/map/data/alert_halo_pulse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pulsation lente de faible amplitude, arrêt sans nouvel appel', (
    tester,
  ) async {
    final samples = <({double radius, double opacity})>[];
    final pulse = AlertHaloPulse(
      paint: (radius, opacity) async =>
          samples.add((radius: radius, opacity: opacity)),
    );
    addTearDown(pulse.stop);
    pulse.start();
    for (var i = 0; i < 30; i++) {
      await tester.pump(AlertHaloPulse.interval);
    }
    expect(samples.length, greaterThan(20));
    expect(samples.any((s) => s.radius > 31.4), isTrue);
    for (final sample in samples) {
      expect(sample.radius, inInclusiveRange(30, 31.5));
      expect(sample.opacity, inInclusiveRange(.22, .28));
    }
    await pulse.stop();
    final count = samples.length;
    await tester.pump(const Duration(seconds: 3));
    expect(samples, hasLength(count));
  });

  testWidgets('plateforme lente : un seul appel, aucun rattrapage accumulé', (
    tester,
  ) async {
    final blocked = Completer<void>();
    var calls = 0;
    final pulse = AlertHaloPulse(
      paint: (_, _) async {
        calls++;
        if (calls == 1) await blocked.future;
      },
    );
    addTearDown(() async {
      if (!blocked.isCompleted) blocked.complete();
      await pulse.stop();
    });
    pulse.start();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    var stopped = false;
    final stopping = pulse.stop().then((_) => stopped = true);
    await tester.pump(const Duration(seconds: 1));
    expect(stopped, isFalse);
    blocked.complete();
    await tester.pump();
    await stopping;
    expect(calls, 1);
    pulse.start();
    await tester.pump(AlertHaloPulse.interval);
    expect(calls, 2);
    await pulse.stop();
  });

  testWidgets('couche indisponible : arrêt au premier échec', (tester) async {
    var calls = 0;
    final pulse = AlertHaloPulse(
      paint: (_, _) async {
        calls++;
        throw StateError('style remplacé');
      },
    );
    addTearDown(pulse.stop);
    pulse.start();
    await tester.pump(AlertHaloPulse.interval);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });
}
