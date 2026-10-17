import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Le zoom se redessine seul pendant les animations, sans reconstruire la carte.
class MapZoomBadge extends StatelessWidget {
  final ValueListenable<double> zoom;

  const MapZoomBadge({super.key, required this.zoom});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: zoom,
    builder: (context, value, _) => Semantics(
      label: 'Niveau de zoom ${value.toStringAsFixed(1)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA).withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Z ${value.toStringAsFixed(1)}',
          style: const TextStyle(color: Color(0xFF243243), fontSize: 11),
        ),
      ),
    ),
  );
}
