import 'package:flutter/material.dart';

import '../domain/manual_report.dart';
import 'report_category_style.dart';

/// Même badge que le repère cartographique : bord blanc, fond de catégorie
/// et pictogramme blanc. Le libellé est porté par le texte voisin.
class ReportCategoryBadge extends StatelessWidget {
  const ReportCategoryBadge({
    super.key,
    required this.category,
    this.size = 48,
  });

  final ReportCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: Colors.white, width: size / 16),
      ),
      child: Icon(category.icon, color: Colors.white, size: size * 0.6),
    ),
  );
}
