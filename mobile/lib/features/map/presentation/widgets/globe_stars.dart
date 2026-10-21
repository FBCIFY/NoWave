import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Screen-fixed space behind the transparent native globe. No animation clock:
/// camera longitude, bearing and gestures cannot move or regenerate the stars.
class GlobeStars extends StatelessWidget {
  const GlobeStars({super.key, required this.zoom});

  final ValueListenable<double> zoom;
  static const spaceColor = Color(0xFF01030B);

  /// Preserve the former native star-intensity zoom stops and their fade.
  static double intensityAt(double zoom) {
    if (!zoom.isFinite || zoom >= 6) return 0;
    if (zoom <= 0) return .65;
    if (zoom <= 3) return .65 + (.4 - .65) * zoom / 3;
    return .4 * (6 - zoom) / 3;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: ColoredBox(
          color: spaceColor,
          child: ValueListenableBuilder<double>(
            valueListenable: zoom,
            builder: (context, value, _) =>
                CustomPaint(painter: _StarfieldPainter(intensityAt(value))),
          ),
        ),
      ),
    ),
  );
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.intensity);

  final double intensity;
  // A stable catalogue survives widget rebuilds, zooms and style reloads.
  static final _stars = _catalogue();

  static List<({double x, double y, double radius, double alpha})>
  _catalogue() {
    final random = math.Random(219);
    return List.generate(
      320,
      (_) => (
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: .25 + math.pow(random.nextDouble(), 3).toDouble() * .7,
        alpha: .3 + random.nextDouble() * .65,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity == 0) return;
    final paint = Paint();
    for (final star in _stars) {
      paint.color = Colors.white.withValues(
        alpha: star.alpha * intensity / .65,
      );
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      intensity != oldDelegate.intensity;
}
