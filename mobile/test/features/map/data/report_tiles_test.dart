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

  test('la zone colorée bat de 1 à 1,25 fois sa taille', () {
    expect(ReportTiles.pulseScale(Duration.zero), 1);
    expect(
      ReportTiles.pulseScale(const Duration(seconds: 1)),
      closeTo(1.25, 1e-9),
    );
    expect(
      ReportTiles.pulseScale(const Duration(seconds: 2)),
      closeTo(1, 1e-9),
    );
    for (var ms = 0; ms <= 2000; ms += 50) {
      final scale = ReportTiles.pulseScale(Duration(milliseconds: ms));
      expect(scale, inInclusiveRange(1, 1.25));
    }
  });

  test('le battement agrandit le rayon à chaque zoom', () {
    // Après ['interpolate', ['linear'], ['zoom']] : des paires zoom/rayon.
    List<num> radii(List<Object> expression) => [
      for (var i = 4; i < expression.length; i += 2) expression[i] as num,
    ];

    final base = radii(ReportTiles.heatmapRadiusExpression());
    final pulsed = radii(ReportTiles.heatmapRadiusExpression(1.25));

    expect(base, [25, 50, 80]);
    expect(pulsed, [for (final r in base) r * 1.25]);
  });
}
