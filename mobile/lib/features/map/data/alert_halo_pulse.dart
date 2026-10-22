import 'dart:async';
import 'dart:math' as math;

/// Pulse uniquement les propriétés du halo natif, sans reconstruire la carte.
class AlertHaloPulse {
  AlertHaloPulse({required this.paint});

  final Future<void> Function(double radius, double opacity) paint;
  static const interval = Duration(milliseconds: 80);
  static const radius = 30.0;
  static const opacity = 0.22;
  Timer? _timer;
  Future<void>? _pending;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (timer) {
      if (_pending != null) return;
      final phase = timer.tick * interval.inMilliseconds / 2200;
      final pulse = (1 - math.cos(phase * math.pi * 2)) / 2;
      _pending = _paint(radius + 1.5 * pulse, opacity + 0.06 * pulse);
    });
  }

  Future<void> _paint(double radius, double opacity) async {
    try {
      await paint(radius, opacity);
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
