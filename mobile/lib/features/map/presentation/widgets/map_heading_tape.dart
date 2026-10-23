import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compas en bandeau en haut de la carte : le cap du téléphone défile sous un
/// repère fixe, la position GPS est centrée juste en dessous.
class MapHeadingTape extends StatelessWidget {
  const MapHeadingTape({
    super.key,
    required this.heading,
    required this.position,
  });

  /// Cap en degrés, null tant que la boussole n'a rien mesuré. Sans modulo :
  /// de 359 à 361, le bandeau passe par le nord au lieu de faire le tour.
  final double? heading;

  /// Ligne de position, déjà formatée (ou message d'état du GPS).
  final String position;

  static const positionKey = ValueKey('map-gps-position');

  /// Degrés visibles d'un bord à l'autre du bandeau.
  static const span = 120.0;
  static const maxWidth = 360.0;
  static const tapeHeight = 40.0;

  /// Glissement entre deux mesures : iOS n'en envoie qu'après 2° de rotation.
  static const glide = Duration(milliseconds: 250);

  /// Même orange que la flèche de position.
  static const accent = Color(0xFFF97316);
  static const _color = Color(0xE6FFFFFF);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];
  static const _figures = [
    FontFeature.liningFigures(),
    FontFeature.tabularFigures(),
  ];

  /// Cap affiché au centre : entier de 000 à 359.
  @visibleForTesting
  static String readout(double? heading) => heading == null
      ? '---'
      : (heading.round() % 360).toString().padLeft(3, '0');

  /// Graduation d'un multiple de 15° : lettre sur les points cardinaux et
  /// intermédiaires, chiffre sinon.
  @visibleForTesting
  static String label(int degrees) {
    final value = degrees % 360;
    if (value % 45 == 0) {
      return const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][value ~/ 45];
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: heading == null
        ? 'Cap indisponible'
        : 'Cap ${readout(heading)} degrés',
    value: position,
    excludeSemantics: true,
    // Repart de la valeur affichée à chaque mesure : le bandeau suit le
    // téléphone sans à-coups.
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: heading ?? 0),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : glide,
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => _tape(heading == null ? null : shown),
    ),
  );

  Widget _tape(double? heading) {
    final value = readout(heading);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: tapeHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TapePainter(
                      heading: heading ?? 0,
                      dimmed: heading == null,
                    ),
                  ),
                ),
                Positioned(
                  top: _TapePainter.labelTop - 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _ReadoutBar(),
                      const SizedBox(width: 9),
                      Text(
                        value,
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          color: heading == null ? _color : accent,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          letterSpacing: 1,
                          fontFeatures: _figures,
                          shadows: _shadow,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const _ReadoutBar(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            position,
            key: positionKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Raleway',
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              fontFeatures: _figures,
              shadows: _shadow,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadoutBar extends StatelessWidget {
  const _ReadoutBar();

  @override
  Widget build(BuildContext context) => Container(
    width: 1.5,
    height: 20,
    decoration: const BoxDecoration(
      color: MapHeadingTape._color,
      boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 2)],
    ),
  );
}

class _TapePainter extends CustomPainter {
  _TapePainter({required this.heading, required this.dimmed});

  final double heading;
  final bool dimmed;

  static const labelTop = 13.0;

  /// Les graduations s'effacent sous le cap affiché au centre.
  static const _readoutClearance = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final perDegree = size.width / MapHeadingTape.span;
    final half = MapHeadingTape.span / 2;
    final first = ((heading - half) / 5).ceil() * 5;
    final tick = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final shadow = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    for (var degrees = first; degrees <= heading + half; degrees += 5) {
      final offset = degrees - heading;
      final x = center + offset * perDegree;
      // Fondu vers les bords, comme un ruban qui s'enroule.
      final fade = 1 - math.pow(offset.abs() / half, 3).toDouble();
      final alpha = fade.clamp(0.0, 1.0) * (dimmed ? 0.45 : 0.9);
      if (alpha <= 0 || offset.abs() < _readoutClearance) continue;
      final major = degrees % 15 == 0;
      final top = major ? 2.0 : 4.0;
      const bottom = 9.0;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), shadow);
      tick.color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), tick);
      if (!major) continue;
      final text = MapHeadingTape.label(degrees);
      final cardinal = (degrees % 360) % 90 == 0;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Raleway',
            color: Color.fromRGBO(255, 255, 255, alpha),
            fontSize: cardinal ? 13 : 11,
            fontWeight: cardinal ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.6,
            fontFeatures: MapHeadingTape._figures,
            shadows: MapHeadingTape._shadow,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(x - painter.width / 2, labelTop + (13 - painter.height) / 2),
      );
      painter.dispose();
    }
    // Pointe sous le cap : le repère fixe du bandeau.
    final pointer = Path()
      ..moveTo(center, size.height - 9)
      ..lineTo(center - 4, size.height - 3)
      ..lineTo(center + 4, size.height - 3)
      ..close();
    canvas.drawShadow(pointer, const Color(0xFF000000), 1.5, false);
    canvas.drawPath(
      pointer,
      Paint()..color = dimmed ? MapHeadingTape._color : MapHeadingTape.accent,
    );
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.heading != heading || old.dimmed != dimmed;
}
