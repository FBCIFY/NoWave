import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/map/presentation/report_marker.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../support/focus_fakes.dart';

class _Http extends Fake implements mb.MapboxHttpService {
  @override
  Future<void> setCustomHeadersForHost(
    String host,
    Map<String, String> headers,
  ) async {
    expect(host, 'example.test');
    expect(headers, {'Authorization': 'Bearer test-token'});
  }
}

class _Map extends FocusMap {
  final _http = _Http();
  @override
  mb.MapboxHttpService get httpService => _http;
}

void main() {
  testWidgets('MVT et sélection partagent les mêmes pixels RGBA de catégorie', (
    tester,
  ) async {
    final map = _Map();
    final tiles = ReportTiles(
      getIdToken: () async => 'test-token',
      apiBaseUrl: 'https://example.test/',
    );
    await tester.runAsync(() => tiles.addTo(map));
    for (final category in ReportCategory.values) {
      final image = map.style.images[ReportMarker.imageId(category)]!;
      expect(image.data, await ReportMarker.paintCategory(category));
      expect(image.data.length, 4 * image.width * image.height);
    }
    final pointLayer = map.style.layers[ReportTiles.pointsLayerId]!;
    expect(
      pointLayer['layout']['icon-image'],
      ReportTiles.markerImageExpression(),
    );
    await tester.runAsync(() => tiles.addTo(map));
    expect(
      map.style.layers.keys.where((id) => id == ReportTiles.pointsLayerId),
      hasLength(1),
    );
    tiles.stopPulse();
  });
}
