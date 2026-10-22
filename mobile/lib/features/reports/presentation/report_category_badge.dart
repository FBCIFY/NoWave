import 'package:flutter/material.dart';

import '../domain/manual_report.dart';
import 'report_category_style.dart';

/// Même badge que le repère cartographique : bord blanc, fond de catégorie
/// et pictogramme blanc. Le libellé est porté par le texte voisin.
class ReportCategoryBadge extends StatelessWidget {
  const ReportCategoryBadge({super.key, required this.category});

  final ReportCategory category;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: category.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(category.icon, color: Colors.white, size: 27),
    ),
  );
}
