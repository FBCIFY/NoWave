import 'package:flutter/material.dart';

import '../domain/manual_report.dart';

/// Apparence d'une catégorie, partagée par le formulaire, la carte et la
/// fiche de détail. Le `switch` oblige à tout définir pour une nouvelle
/// catégorie. Le pictogramme est dans `report_category_icon.dart`.
extension ReportCategoryStyle on ReportCategory {
  String get label => switch (this) {
    ReportCategory.marineAnimal => 'Animal marin',
    ReportCategory.obstruction => 'Obstacle',
    ReportCategory.pollution => 'Pollution',
  };

  /// Couleur du badge sur la carte.
  Color get color => switch (this) {
    ReportCategory.marineAnimal => const Color(0xFF06B6D4),
    ReportCategory.obstruction => const Color(0xFFF97316),
    ReportCategory.pollution => const Color(0xFF7C3AED),
  };
}
