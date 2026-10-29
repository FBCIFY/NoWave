import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaque catégorie a son propre badge sur la carte', () {
    final expression = ReportTiles.markerImageExpression();

    expect(expression.take(2), [
      'match',
      ['get', 'category'],
    ]);
    // Après l'opérateur : des paires valeur/badge, puis le badge par défaut.
    final pairs = expression.sublist(2, expression.length - 1);
    final markers = {
      for (var i = 0; i < pairs.length; i += 2) pairs[i]: pairs[i + 1],
    };

    expect(markers.keys, ReportCategory.values.map((c) => c.apiValue));
    expect(markers.values.toSet(), hasLength(ReportCategory.values.length));
    expect(markers.values, isNot(contains(expression.last)));
  });

  test('la zone colorée garde un rayon fixe à chaque zoom', () {
    const expression = ReportTiles.heatmapRadiusExpression;
    // Après ['interpolate', ['linear'], ['zoom']] : des paires zoom/rayon.
    final radii = [
      for (var i = 4; i < expression.length; i += 2) expression[i] as num,
    ];

    expect(radii, [25, 50, 80]);
  });

  test(
    'zones colorées du violet au rouge foncé, transparentes sur les bords',
    () {
      const expression = ReportTiles.heatmapColorExpression;
      // Après ['interpolate', ['linear'], ['heatmap-density']] : des paires
      // densité/couleur.
      final stops = [
        for (var i = 3; i < expression.length; i += 2) expression[i] as num,
      ];
      final colors = [
        for (var i = 4; i < expression.length; i += 2) expression[i],
      ];

      expect(stops.first, 0);
      expect(stops.last, 1);
      expect(stops, orderedEquals([...stops]..sort()));
      expect(colors.first, 'rgba(139, 92, 246, 0)');
      expect(colors.last, 'rgb(110, 20, 20)');
      expect(colors, contains('rgba(59, 130, 246, 0.55)'));
      expect(colors, contains('rgba(34, 197, 94, 0.7)'));
      // L'opacité monte du bord vers le centre.
      final alphas = [
        for (final color in colors.cast<String>())
          color.startsWith('rgba')
              ? double.parse(color.split(',').last.replaceAll(')', ''))
              : 1.0,
      ];
      expect(alphas, orderedEquals([...alphas]..sort()));
    },
  );

  test('reconnaît un refus d’accès aux tuiles', () {
    const prefix = 'Failed to load tile: HTTP status code';

    expect(ReportTiles.isForbidden('$prefix 403'), isTrue);
    expect(ReportTiles.isForbidden('$prefix 401'), isFalse);
    expect(ReportTiles.isForbidden('$prefix 4030'), isFalse);
  });
}
