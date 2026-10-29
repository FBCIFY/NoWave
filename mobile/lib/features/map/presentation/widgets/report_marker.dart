import 'package:flutter/material.dart';

/// Repère du point à signaler, fixe pendant que la carte bouge dessous. Il se
/// soulève quand la carte est déplacée, et une petite ombre marque alors le
/// point visé ; il se pose quand la carte s'arrête.
///
/// Seule l'icône monte : la boîte reste en place, car la carte y lit la pointe
/// du repère pour calculer les coordonnées.
class ReportMarker extends StatelessWidget {
  const ReportMarker({super.key, required this.lifted});

  final bool lifted;

  static const size = 44.0;

  /// Écart entre la pointe de l'icône et le bas de la boîte.
  static const tipInset = 4.0;

  static const _liftDuration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size / 2 - 6,
            top: size - tipInset - 2.5,
            width: 12,
            height: 5,
            child: AnimatedOpacity(
              opacity: lifted ? 1 : 0,
              duration: _liftDuration,
              child: const DecoratedBox(
                decoration: ShapeDecoration(
                  color: Color(0x66000000),
                  shape: OvalBorder(),
                ),
              ),
            ),
          ),
          AnimatedSlide(
            // Un quart de l'icône, soit 11 px.
            offset: Offset(0, lifted ? -0.25 : 0),
            duration: _liftDuration,
            curve: Curves.easeOut,
            child: const Icon(
              Icons.place,
              color: Color(0xFF0DB8D5),
              size: size,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
  }
}
