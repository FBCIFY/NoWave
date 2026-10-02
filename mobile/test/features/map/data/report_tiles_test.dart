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
}
