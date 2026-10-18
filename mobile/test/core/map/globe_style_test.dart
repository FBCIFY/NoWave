import 'dart:convert';
import 'dart:io';

import 'package:blueway/core/map/globe_presentation.dart';
import 'package:blueway/core/map/globe_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Map extends Fake implements MapboxMap {
  @override
  final _Style style = _Style();
}

class _Style extends Fake implements StyleManager {
  final calls = <Map<String, Object?>>[];
  bool fail = false;

  @override
  Future<void> setStyleImportConfigProperties(
    String id,
    Map<String, Object?> properties,
  ) async {
    expect(id, 'basemap');
    if (fail) throw PlatformException(code: 'style-not-ready');
    calls.add(properties);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native style preserves Standard and bounded, georeferenced decoration',
    () {
      final document = GlobeStyle.document(Uri.parse('file:///globe/'));
      expect(jsonDecode(jsonEncode(document))['projection']['name'], 'globe');
      final basemap = (document['imports'] as List).single as Map;
      expect(basemap['id'], 'basemap');
      expect(basemap['url'], 'mapbox://styles/mapbox/standard');
      final sources = document['sources'] as Map;
      expect(document['center'], [15.0, 12.0]);
      expect(document['zoom'], GlobeStyle.initialZoom);
      expect(
        sources[GlobeStyle.creditsSource]['attribution'],
        contains('NASA'),
      );
      expect(sources[GlobeStyle.creditsSource]['data']['features'], isEmpty);
      expect(sources[GlobeStyle.satelliteSource]['maxzoom'], 7);
      expect(sources[GlobeStyle.satelliteSource]['prefetch-zoom-delta'], 0);
      for (final name in GlobeStyle.imageNames) {
        final source = sources['nowave-clouds-$name'];
        expect(source['url'], 'file:///globe/$name.png');
        final coordinates = source['coordinates'] as List<List<double>>;
        expect(coordinates[1][0] - coordinates[0][0], 180);
        expect(coordinates[0][1], greaterThan(coordinates[2][1]));
      }
      final layers = document['layers'] as List;
      expect(layers.map((l) => l['id']).toSet().length, layers.length);
      for (final layer in layers) {
        expect(layer['slot'], 'bottom');
        expect(layer['maxzoom'], lessThanOrEqualTo(7));
      }
      final ocean = layers.singleWhere((l) => l['id'] == 'nowave-earth-ocean');
      expect(ocean['source-layer'], 'water');
      expect(ocean['source'], GlobeStyle.waterSource);
    },
  );

  test(
    'bundle exports a valid local style with all four actual raster files',
    () async {
      final uri = await GlobeStyle.prepare();
      final style =
          jsonDecode(await File.fromUri(Uri.parse(uri)).readAsString()) as Map;
      for (final source in (style['sources'] as Map).values) {
        if (source['type'] != 'image') continue;
        final file = File.fromUri(Uri.parse(source['url'] as String));
        expect(await file.exists(), isTrue);
        final bytes = await file.readAsBytes();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(ByteData.sublistView(bytes).getUint32(16), 512);
        expect(ByteData.sublistView(bytes).getUint32(20), 512);
      }
    },
  );

  test(
    'labels: crossing only, both directions, reload, retry after failure',
    () async {
      final map = _Map();
      final presentation = GlobePresentation();
      for (final zoom in [
        .65,
        1.0,
        3.9,
        4.0,
        6.0,
        9.0,
        12.0,
        14.0,
        16.0,
        3.0,
      ]) {
        await presentation.synchronize(map, zoom);
      }
      expect(map.style.calls.map((c) => c['showPlaceLabels']), [
        false,
        true,
        false,
      ]);
      presentation.styleLoaded();
      await presentation.synchronize(map, .65);
      expect(map.style.calls.length, 4);
      map.style.fail = true;
      await presentation.synchronize(map, 6);
      map.style.fail = false;
      await presentation.synchronize(map, 6);
      expect(map.style.calls.last['showPlaceLabels'], true);
      expect(map.style.calls.last['showAdminBoundaries'], true);
    },
  );
}
