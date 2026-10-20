import 'dart:ui' as ui;

import 'package:blueway/features/map/data/harbour_layer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/map/marine/marine_map_controller_test.dart'
    show MarineMap;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ports Z6, taille fluide et bornée, collisions et aucun filtre de rang',
    () {
      final layer = HarbourLayer.layer();
      expect(layer.minZoom, 6.0);
      expect(layer.maxZoom, isNull);
      expect(layer.iconAllowOverlap, false);
      expect(layer.iconIgnorePlacement, false);
      expect(layer.iconSizeExpression, [
        'interpolate',
        ['linear'],
        ['zoom'],
        6,
        .62,
        8,
        .72,
        10,
        .85,
        12,
        1.0,
        14,
        1.08,
        18,
        1.12,
      ]);
      expect(layer.filter, [
        '==',
        ['geometry-type'],
        'Point',
      ]);
      expect(layer.iconImageExpression.toString(), contains('marina'));
    },
  );

  testWidgets('source réelle Z6, images transparentes 3x, reload idempotent', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final map = MarineMap();
      await Future.wait([
        HarbourLayer.addTo(map, apiBaseUrl: 'http://127.0.0.1:8004/'),
        HarbourLayer.addTo(map, apiBaseUrl: 'http://127.0.0.1:8004/'),
      ]);
      expect(map.style.sources.length, 1);
      expect(map.style.layers.length, 1);
      final source = map.style.sources[HarbourLayer.sourceId]!;
      expect(source['minzoom'], 6);
      expect(source['maxzoom'], 14);
      expect(source['tiles'], [
        'http://127.0.0.1:8004/api/v1/map/harbours/{z}/{x}/{y}.pbf',
      ]);
      expect(map.style.images.length, 2);
      for (final marina in [false, true]) {
        final icon = await HarbourLayer.icon(marina: marina);
        expect(icon.width, 72);
        final codec = await ui.instantiateImageCodec(icon.data);
        final frame = await codec.getNextFrame();
        final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
        expect(rgba[3], 0);
        expect([
          for (var i = 3; i < rgba.length; i += 4) rgba[i],
        ], contains(255));
        frame.image.dispose();
        codec.dispose();
      }
      map.style.sources.clear();
      map.style.layers.clear();
      map.style.images.clear();
      await HarbourLayer.addTo(map, apiBaseUrl: 'http://127.0.0.1:8004/');
      expect(map.style.sources.length, 1);
      expect(map.style.layers.length, 1);
      expect(map.style.images.length, 2);
    });
  });
}
