import 'dart:async';

import 'package:blueway/features/map/data/alert_halo_pulse.dart';
import 'package:blueway/features/reports/domain/report_reach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ondes décalées, expansion continue et opacité de 100 à 0 %', () {
    final first = AlertHaloPulse.wavesAt(Duration.zero);
    expect(first, [(progress: 0.0, opacity: 1.0)]);
    final middle = AlertHaloPulse.wavesAt(const Duration(milliseconds: 3000));
    expect(middle, hasLength(2));
    expect(middle.first, (progress: .5, opacity: .5));
    final end = AlertHaloPulse.wavesAt(const Duration(milliseconds: 5999));
    expect(end, hasLength(3));
    expect(end.first.progress, greaterThan(.999));
    expect(end.first.opacity, lessThan(.001));
    final next = AlertHaloPulse.wavesAt(AlertHaloPulse.travel);
    expect(next.first, (progress: 0.0, opacity: 1.0));
    expect(next[1].progress, closeTo(2 / 3, .0001));
    expect(next[2].progress, closeTo(1 / 3, .0001));
  });

  test(
    'cercles géographiques : arrivée à la distance du bateau sans dépasser',
    () {
      final distance = ReportReach.distance(43.29, 5.373, 43.30, 5.37);
      final data = AlertHaloPulse.data(
        latitude: 43.29,
        longitude: 5.373,
        distanceMeters: distance,
        waves: [(progress: .5, opacity: .5), (progress: 1, opacity: 0)],
      );
      final features = data['features']! as List;
      for (var i = 0; i < features.length; i++) {
        final points = features[i]['geometry']['coordinates'] as List;
        expect(points, hasLength(73));
        expect(features[i]['properties']['opacity'], i == 0 ? .5 : 0);
        for (final point in points) {
          expect(
            ReportReach.distance(
              43.29,
              5.373,
              point[1] as double,
              point[0] as double,
            ),
            closeTo(distance * (i == 0 ? .5 : 1), .01),
          );
        }
        expect(points.last[0], closeTo(points.first[0] as double, 1e-8));
        expect(points.last[1], closeTo(points.first[1] as double, 1e-8));
      }
    },
  );

  testWidgets(
    'animation du sonar : progression régulière puis arrêt sans rappel',
    (tester) async {
      final samples = <List<AlertSonarWave>>[];
      final sonar = AlertHaloPulse(paint: (waves) async => samples.add(waves));
      sonar.start();
      for (var i = 0; i < 60; i++) {
        await tester.pump(AlertHaloPulse.interval);
      }
      expect(samples.length, greaterThan(30));
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i].first.progress,
          greaterThan(samples[i - 1].first.progress),
        );
        expect(
          samples[i].first.opacity,
          lessThan(samples[i - 1].first.opacity),
        );
      }
      await sonar.stop();
      final count = samples.length;
      await tester.pump(const Duration(seconds: 5));
      expect(samples, hasLength(count));
    },
  );

  testWidgets('plateforme lente : un seul appel, aucun rattrapage accumulé', (
    tester,
  ) async {
    final blocked = Completer<void>();
    var calls = 0;
    final sonar = AlertHaloPulse(
      paint: (_) async {
        calls++;
        if (calls == 1) await blocked.future;
      },
    );
    sonar.start();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    var stopped = false;
    final stopping = sonar.stop().then((_) => stopped = true);
    await tester.pump(const Duration(seconds: 1));
    expect(stopped, isFalse);
    blocked.complete();
    await tester.pump();
    await stopping;
    expect(calls, 1);
    sonar.start();
    await tester.pump(AlertHaloPulse.interval);
    expect(calls, greaterThan(1));
    await sonar.stop();
  });

  testWidgets('couche indisponible : arrêt au premier échec', (tester) async {
    var calls = 0;
    final sonar = AlertHaloPulse(
      paint: (_) async {
        calls++;
        throw StateError('style remplacé');
      },
    );
    sonar.start();
    await tester.pump(AlertHaloPulse.interval);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await sonar.stop();
  });
}
