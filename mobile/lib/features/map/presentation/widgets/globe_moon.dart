import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Decorative LRO near side. No ephemeris, gesture handling or animation loop.
/// At low zoom it sits beyond the lower right limb and clear of the controls.
class GlobeMoon extends StatelessWidget {
  const GlobeMoon({super.key, required this.zoom});

  final ValueListenable<double> zoom;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: ValueListenableBuilder<double>(
        valueListenable: zoom,
        builder: (context, value, child) {
          final opacity = ((1.1 - value) / 0.45).clamp(0.0, 1.0);
          if (opacity == 0) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final diameter = (width * 0.056).clamp(12.0, 28.0);
              return Stack(
                children: [
                  Positioned(
                    left: width * 0.84 - diameter / 2,
                    top: constraints.maxHeight / 2 + width * 0.39,
                    width: diameter,
                    height: diameter,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                ],
              );
            },
          );
        },
        child: Image.asset(
          'assets/globe/moon.png',
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
