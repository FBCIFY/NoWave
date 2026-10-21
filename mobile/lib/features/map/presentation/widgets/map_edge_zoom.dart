import 'package:flutter/material.dart';

/// Bandes invisibles le long des bords gauche et droit de la carte : glisser
/// vers le bas zoome, vers le haut dézoome. Remplace le double tap + glissé
/// de Mapbox, désactivé parce qu'il se déclenchait sans le vouloir.
class MapEdgeZoom extends StatelessWidget {
  /// Assez large pour le pouce, assez fine pour laisser la carte au glissé.
  static const width = 24.0;

  /// Distance du doigt pour un niveau de zoom.
  static const pixelsPerZoom = 150.0;

  final VoidCallback onStart;
  final ValueChanged<double> onZoom;

  const MapEdgeZoom({super.key, required this.onStart, required this.onZoom});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final left in [true, false])
        Positioned(
          top: 0,
          bottom: 0,
          left: left ? 0 : null,
          right: left ? null : 0,
          width: width,
          child: GestureDetector(
            key: ValueKey(left ? 'edge-zoom-left' : 'edge-zoom-right'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => onStart(),
            onVerticalDragUpdate: (details) =>
                onZoom(details.delta.dy / pixelsPerZoom),
          ),
        ),
    ],
  );
}
