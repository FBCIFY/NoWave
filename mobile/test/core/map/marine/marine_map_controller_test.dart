import 'dart:convert';

import 'package:blueway/core/map/land_colors.dart';

import 'package:blueway/core/map/marine/marine_map_controller.dart';
import 'package:blueway/features/map/data/hydrography_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MarineMap extends Fake implements MapboxMap {
  @override
  final MarineStyle style = MarineStyle();
}

class MarineStyle extends Fake implements StyleManager {
  final sources = <String, Map>{};
  final layers = <String, Map>{};
  final images = <String>{};
  final config = <String, Object>{};
  bool reject = false;
  @override
  Future<void> setProjection(StyleProjection projection) async {}
  @override
  Future<void> setStyleImportConfigProperty(
    String id,
    String config,
    Object value,
  ) async {
    expect(id, 'basemap');
    this.config[config] = value;
  }

  @override
  Future<bool> styleSourceExists(String id) async => sources.containsKey(id);
  @override
  Future<bool> styleLayerExists(String id) async => layers.containsKey(id);
  @override
  Future<void> setStyleSourceProperty(
    String id,
    String property,
    Object value,
  ) async {
    (sources[id] as Map)[property] = value;
  }

  @override
  Future<void> setStyleSourceProperties(String id, String properties) async {
    sources[id]!.addAll(jsonDecode(properties) as Map);
  }

  @override
  Future<void> addStyleSource(String id, String properties) async {
    if (reject) throw PlatformException(code: 'source-failure');
    expect(sources.containsKey(id), isFalse);
    sources[id] = jsonDecode(properties) as Map;
  }

  @override
  Future<void> addStyleLayer(String properties, LayerPosition? position) async {
    final layer = jsonDecode(properties) as Map;
    expect(layers.containsKey(layer['id']), isFalse);
    layers[layer['id'] as String] = layer;
  }

  @override
  Future<bool> hasStyleImage(String id) async => images.contains(id);
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
    images.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const local = 'http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png';
  const global =
      'http://127.0.0.1:8004/api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp';

  test(
    'raster local unique, opaque aux zooms utiles, overzoom et reload',
    () async {
      final map = MarineMap();
      final marine = MarineMapController(
        bathymetryTilesUrl: local,
        globalSeafloorTilesUrl: global,
      );
      await marine.install(map);
      await marine.install(map);
      expect(map.style.sources.length, 2);
      expect(map.style.layers.length, 2);
      final source = map.style.sources[MarineMapController.bathymetrySourceId]!;
      final layer = map.style.layers[MarineMapController.bathymetryLayerId]!;
      expect(map.style.config['colorLand'], LandColors.color('#C4AD80'));
      expect(map.style.config['colorGreenspace'], LandColors.color('#627545'));
      expect(map.style.config['colorWater'], '#002D51');
      expect(map.style.config['showRoadLabels'], false);
      expect(map.style.config['showPointOfInterestLabels'], false);
      expect(source['tiles'], ['$local?v=marine-visual-7']);
      expect(source['maxzoom'], 14);
      expect(source['minzoom'], 5);
      expect(source['bounds'], [-73.125, 5.625, 45, 85.051129]);
      expect(source['tile-network-requests-delay'], .6);
      final base = map.style.sources[MarineMapController.globalSourceId]!;
      expect(base['tiles'], [global]);
      expect(base['minzoom'], 0);
      expect(base['maxzoom'], 6);
      expect(base['prefetch-zoom-delta'], 4);
      expect(base['tile-network-requests-delay'], 0);
      expect(base['volatile'], false);
      expect(base['bounds'], isNull);
      expect(base['attribution'], contains('GEBCO 2026'));
      final baseLayer = map.style.layers[MarineMapController.globalLayerId]!;
      expect(baseLayer['minzoom'], isNull);
      expect(baseLayer['maxzoom'], isNull);
      expect(baseLayer['slot'], 'middle');
      expect(baseLayer['paint']['raster-opacity'], 1);
      expect(
        source['attribution'],
        contains(
          'Couleurs interpolées localement pour l’affichage, sans mesure ajoutée.',
        ),
      );
      expect(
        source['attribution'],
        contains('https://emodnet.ec.europa.eu/en/bathymetry'),
      );
      expect(source['volatile'], false);
      expect(source['prefetch-zoom-delta'], 4);
      expect(layer['slot'], 'middle');
      expect(layer['minzoom'], 5); // No marine tile requests in globe view.
      expect(layer['maxzoom'], isNull); // Z14 tiles remain eligible at Z17+.
      expect(layer['paint']['raster-opacity'], 1);
      expect(layer['paint']['raster-resampling'], 'linear');
      expect(layer['paint']['raster-contrast'], 0);
      expect(layer['paint']['raster-saturation'], 0);
      map.style.sources.clear();
      map.style.layers.clear();
      await marine.install(map);
      expect(
        map.style.sources[MarineMapController.bathymetrySourceId]!['tiles'],
        ['$local?v=marine-visual-7'],
      );
      expect(map.style.layers.length, 2);
    },
  );

  test(
    'fond mondial et détails utilisent la même base avec son préfixe',
    () async {
      final map = MarineMap();
      await MarineMapController(apiBaseUrl: 'https://marine.test/prefix/')
          .install(map);
      expect(map.style.sources[MarineMapController.globalSourceId]!['tiles'], [
        'https://marine.test/prefix/api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp',
      ]);
      expect(
        map.style.sources[MarineMapController.bathymetrySourceId]!['tiles'],
        [
          'https://marine.test/prefix/api/v1/map/bathymetry/{z}/{x}/{y}.png?v=marine-visual-7',
        ],
      );
    },
  );

  test('absence de source sans configuration bathymétrique', () async {
    final map = MarineMap();
    await MarineMapController(bathymetryTilesUrl: '').install(map);
    expect(map.style.sources, isEmpty);
    expect(map.style.layers, isEmpty);
  });

  test('version du masque sans perdre les paramètres existants', () async {
    final map = MarineMap();
    await MarineMapController(
      bathymetryTilesUrl: '$local?region=europe',
      globalSeafloorTilesUrl: global,
    ).install(map);
    expect(
      map.style.sources[MarineMapController.bathymetrySourceId]!['tiles'],
      ['$local?region=europe&v=marine-visual-7'],
    );
  });

  test('installation réessayable après une erreur du style', () async {
    final map = MarineMap()..style.reject = true;
    final marine = MarineMapController(
      bathymetryTilesUrl: local,
      globalSeafloorTilesUrl: global,
    );
    await expectLater(marine.install(map), throwsA(isA<PlatformException>()));
    map.style.reject = false;
    await marine.install(map);
    expect(map.style.layers.length, 2);
  });

  test('raster en fond, isobathes et chiffres au-dessus', () async {
    final map = MarineMap();
    await MarineMapController(
      bathymetryTilesUrl: local,
      globalSeafloorTilesUrl: global,
    ).install(map);
    expect(map.style.layers.keys.toList(), [
      MarineMapController.globalLayerId,
      MarineMapController.bathymetryLayerId,
    ]);
    for (final layer in HydrographyLayer.layers().whereType<LineLayer>().where(
      (l) => l.sourceLayer == 'depth_contour',
    )) {
      expect(layer.slot, LayerSlot.MIDDLE);
    }
    expect(
      (HydrographyLayer.layers().singleWhere(
        (l) => l.id == 'nowave-depth-labels',
      )).slot,
      LayerSlot.MIDDLE,
    );
  });
}
