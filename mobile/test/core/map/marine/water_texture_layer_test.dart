import 'dart:convert';
import 'dart:ui' as ui;

import 'package:blueway/core/map/marine/water_texture_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class TextureMap extends Fake implements MapboxMap {
  @override
  final TextureStyle style = TextureStyle();
}

class TextureStyle extends Fake implements StyleManager {
  final images = <String, MbxImage>{};
  final sources = <String, dynamic>{};
  final layers = <String, dynamic>{};
  bool rejectSource = false;

  @override
  Future<bool> hasStyleImage(String id) async => images.containsKey(id);
  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> addStyleImage(
    String id,
    double scale,
    MbxImage image,
    bool sdf,
    List<ImageStretches?> x,
    List<ImageStretches?> y,
    ImageContent? content,
  ) async {
    expect(images.containsKey(id), isFalse);
    images[id] = image;
  }

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {}
  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (rejectSource) throw PlatformException(code: 'offline');
    expect(sources.containsKey(id), isFalse);
    sources[id] = jsonDecode(properties);
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map;
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('texture : concurrence, reload et reprise après panne', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final map = TextureMap();
      final texture = WaterTextureLayer();
      await Future.wait([texture.addTo(map), texture.addTo(map)]);
      expect(map.style.sources.length, 1);
      expect(map.style.layers.length, 1);
      final image = map.style.images.values.single;
      final codec = await ui.instantiateImageCodec(image.data);
      final frame = await codec.getNextFrame();
      final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
      expect(rgba.length, 512 * 512 * 4);
      frame.image.dispose();
      codec.dispose();
      final alpha = [for (var i = 3; i < rgba.length; i += 4) rgba[i]];
      // Le motif comporte des traits et laisse l'essentiel du raster intact.
      expect(alpha.any((a) => a > 0), isTrue);
      expect(
        alpha.where((a) => a == 0).length / alpha.length,
        greaterThan(.85),
      );
      map.style.images.clear();
      map.style.sources.clear();
      map.style.layers.clear();
      map.style.rejectSource = true;
      await expectLater(texture.addTo(map), throwsA(isA<PlatformException>()));
      map.style.rejectSource = false;
      await texture.addTo(map);
      expect(identical(map.style.images.values.single, image), isTrue);
      expect(map.style.layers.values.single['source-layer'], 'water');
      expect(map.style.layers.values.single['slot'], 'bottom');
    });
  });
}
