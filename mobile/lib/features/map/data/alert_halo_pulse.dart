import 'dart:async';
import 'dart:math' as math;

import '../../reports/domain/report_reach.dart';

typedef AlertSonarWave = ({double progress, double opacity});

/// Ondes géographiques du sonar, sans reconstruire la carte ni sa caméra.
class AlertHaloPulse {
  AlertHaloPulse({required this.paint});

  final Future<void> Function(List<AlertSonarWave> waves) paint;
  static const interval = Duration(milliseconds: 32);
  static const travel = Duration(milliseconds: 6000);
  static const empty = {'type': 'FeatureCollection', 'features': <Object>[]};
  Timer? _timer;
  Future<void>? _pending;

  /// Trois fronts décalés : chaque cercle grandit puis disparaît à destination.
  static List<AlertSonarWave> wavesAt(Duration elapsed) => [
    for (var i = 0; i < 3; i++)
      if (elapsed.inMilliseconds >= i * travel.inMilliseconds ~/ 3)
        () {
          final age = elapsed.inMilliseconds - i * travel.inMilliseconds ~/ 3;
          final progress =
              (age % travel.inMilliseconds) / travel.inMilliseconds;
          return (progress: progress, opacity: 1 - progress);
        }(),
  ];

  /// Le dernier front atteint la distance du bateau, indépendamment du zoom.
  static Map<String, Object> data({
    required double latitude,
    required double longitude,
    required double distanceMeters,
    required List<AlertSonarWave> waves,
  }) => {
    'type': 'FeatureCollection',
    'features': [
      if (distanceMeters.isFinite && distanceMeters > 0)
        for (final wave in waves)
          {
            'type': 'Feature',
            'properties': {'opacity': wave.opacity},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (var step = 0; step <= 72; step++)
                  () {
                    final point = ReportReach.destination(
                      latitude,
                      longitude,
                      step * math.pi * 2 / 72,
                      distanceMeters * wave.progress,
                    );
                    return [point.longitude, point.latitude];
                  }(),
              ],
            },
          },
    ],
  };

  void start() {
    if (_timer != null) return;
    _pending ??= _paint(wavesAt(Duration.zero));
    _timer = Timer.periodic(interval, (timer) {
      if (_pending != null) return;
      _pending = _paint(wavesAt(interval * timer.tick));
    });
  }

  Future<void> _paint(List<AlertSonarWave> waves) async {
    try {
      await paint(waves);
    } catch (_) {
      _timer?.cancel();
      _timer = null;
    } finally {
      _pending = null;
    }
  }

  /// Attend aussi l'appel natif en cours avant de remplacer/retirer la couche.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _pending;
  }
}
