import 'package:flutter/material.dart';

import '../domain/manual_report.dart';

/// Pictogramme d'une catégorie. Material n'a pas de dauphin : il est dessiné
/// en vectoriel, les autres viennent de la police d'icônes. Le même dessin
/// sert aux badges de la carte (PNG) et aux écrans.
extension ReportCategoryGlyph on ReportCategory {
  /// Dessine le pictogramme centré sur [center], dans un carré de [size].
  void paintIcon(Canvas canvas, Offset center, double size, Color color) {
    switch (this) {
      case ReportCategory.marineAnimal:
        _paintDolphin(canvas, center, size, color);
      case ReportCategory.obstruction:
        paintIconData(canvas, Icons.warning_amber_rounded, center, size, color);
      case ReportCategory.pollution:
        paintIconData(canvas, Icons.water_drop_outlined, center, size, color);
    }
  }
}

/// Dessine une icône de police comme le ferait [Icon], centrée sur [center].
void paintIconData(
  Canvas canvas,
  IconData icon,
  Offset center,
  double size,
  Color color,
) {
  final glyph = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  glyph.paint(canvas, center - Offset(glyph.width / 2, glyph.height / 2));
  glyph.dispose();
}

/// Dauphin de profil, tête à droite, dessiné dans une boîte 24 × 24 ;
/// l'œil est découpé.
final Path _dolphin = Path.combine(
  PathOperation.difference,
  Path()
    ..moveTo(22.5, 12.6)
    ..cubicTo(21.5, 12.0, 20.5, 11.9, 19.8, 11.6)
    ..cubicTo(19.2, 9.6, 17.6, 8.6, 15.2, 8.5)
    ..cubicTo(14.4, 7.2, 13.2, 5.6, 11.4, 5.0)
    ..cubicTo(11.9, 6.2, 11.9, 7.6, 11.6, 8.7)
    ..cubicTo(8.6, 9.3, 6.0, 11.0, 4.4, 13.6)
    ..cubicTo(3.6, 12.8, 2.4, 12.2, 1.2, 12.3)
    ..cubicTo(2.0, 13.6, 2.8, 14.6, 3.6, 15.0)
    ..cubicTo(3.0, 16.0, 2.6, 17.2, 2.6, 18.3)
    ..cubicTo(3.9, 17.6, 4.9, 16.6, 5.4, 15.4)
    ..cubicTo(8.2, 13.6, 11.5, 13.4, 14.6, 14.2)
    ..cubicTo(14.2, 15.4, 13.4, 16.6, 12.4, 17.2)
    ..cubicTo(14.2, 17.2, 15.8, 16.2, 16.8, 14.6)
    ..cubicTo(18.8, 14.4, 20.8, 13.6, 22.5, 12.6)
    ..close(),
  Path()
    ..addOval(Rect.fromCircle(center: const Offset(18.4, 11.2), radius: .7)),
);
final Rect _dolphinBounds = _dolphin.getBounds();

/// Largeur du dauphin rapportée au carré de l'icône : un peu plus large que
/// les icônes Material pour peser autant à l'œil, la silhouette étant basse.
const _dolphinWidth = .94;

void _paintDolphin(Canvas canvas, Offset center, double size, Color color) {
  final scale = size * _dolphinWidth / _dolphinBounds.width;
  canvas
    ..save()
    ..translate(center.dx, center.dy)
    ..scale(scale)
    ..translate(-_dolphinBounds.center.dx, -_dolphinBounds.center.dy)
    ..drawPath(_dolphin, Paint()..color = color)
    ..restore();
}

/// Équivalent de [Icon] pour une catégorie : taille et couleur suivent
/// l'[IconTheme] quand elles ne sont pas données.
class ReportCategoryIcon extends StatelessWidget {
  const ReportCategoryIcon(this.category, {super.key, this.color, this.size});

  final ReportCategory category;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _ReportCategoryIconPainter(
          category,
          color ?? theme.color ?? Colors.black,
        ),
      ),
    );
  }
}

class _ReportCategoryIconPainter extends CustomPainter {
  const _ReportCategoryIconPainter(this.category, this.color);

  final ReportCategory category;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => category.paintIcon(
    canvas,
    size.center(Offset.zero),
    size.shortestSide,
    color,
  );

  @override
  bool shouldRepaint(_ReportCategoryIconPainter old) =>
      old.category != category || old.color != color;
}
