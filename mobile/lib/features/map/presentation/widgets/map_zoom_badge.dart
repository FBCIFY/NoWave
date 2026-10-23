import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'map_action_rail.dart';

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
        // Même fond que la barre d'actions.
        decoration: BoxDecoration(
          color: MapActionRail.background(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MapActionRail.border),
        ),
        child: Text(
          'Z ${value.toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    ),
  );
}
