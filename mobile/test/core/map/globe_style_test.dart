import 'dart:convert';
import 'dart:io';

import 'package:blueway/core/map/globe_presentation.dart';
import 'package:blueway/core/map/globe_style.dart';
import 'package:blueway/core/map/land_colors.dart';
import 'package:blueway/core/map/marine/marine_map_controller.dart';
import 'package:blueway/core/map/marine/marine_palette.dart';
import 'package:blueway/core/map/marine/marine_zoom.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class _Map extends Fake implements MapboxMap {
  @override
  final _Style style = _Style();
}

class _Style extends Fake implements StyleManager {
  final calls = <Map<String, Object?>>[];
  final config = <String, Object>{'lightPreset': 'day', 'theme': 'faded'};
  bool fail = false;

  @override
  Future<void> setProjection(StyleProjection projection) async {}

  @override
  Future<void> setStyleImportConfigProperties(
    String id,
    Map<String, Object?> properties,
  ) async {
    expect(id, 'basemap');
    if (fail) throw PlatformException(code: 'style-not-ready');
    // Native Mapbox replaces the whole import configuration with this API.
    config
      ..clear()
      ..addAll(properties.cast<String, Object>());
    calls.add(properties);
  }

  @override
  Future<void> setStyleImportConfigProperty(
    String id,
    String property,
    Object value,
  ) async {
    expect(id, 'basemap');
    if (fail) throw PlatformException(code: 'style-not-ready');
    config[property] = value;
    calls.add({property: value});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native style preserves Standard with real vector classes and no imagery',
    () {
      final document = GlobeStyle.document(Uri.parse('file:///globe/'));
      expect(jsonDecode(jsonEncode(document))['projection']['name'], 'globe');
      final basemap = (document['imports'] as List).single as Map;
      expect(basemap['id'], 'basemap');
      expect(basemap['url'], 'mapbox://styles/mapbox/standard');
      expect(basemap['config']['colorLand'], LandColors.color('#C4AD80'));
      expect(basemap['config']['colorGreenspace'], LandColors.color('#627545'));
      expect(basemap['config']['showRoadLabels'], false);
      expect(basemap['config']['showAdminBoundaries'], false);
      final sources = document['sources'] as Map;
      expect(sources[GlobeStyle.waterSource]['type'], 'vector');
      expect(
        sources[GlobeStyle.waterSource]['url'],
        'mapbox://mapbox.mapbox-streets-v8',
      );
      expect(document['center'], [15.0, 12.0]);
      expect(document['zoom'], GlobeStyle.initialZoom);
      expect(
        sources.keys,
        unorderedEquals([GlobeStyle.waterSource, GlobeStyle.terrainSource]),
      );
      expect(sources.values.every((s) => s['type'] == 'vector'), isTrue);
      final layers = document['layers'] as List;
      expect(layers.map((l) => l['id']).toSet().length, layers.length);
      expect(jsonEncode(document), isNot(contains('satellite')));
      expect(jsonEncode(document), isNot(contains('cloud')));
      expect(jsonEncode(document), isNot(contains('moon')));
      final cover = layers.singleWhere((l) => l['id'] == 'nowave-landcover');
      expect(cover['source-layer'], 'landcover');
      expect(cover['slot'], 'bottom');
      for (final layer in layers.where((l) => l['source-layer'] == 'admin')) {
        expect(layer['paint']['line-opacity'], .18);
        expect(layer['paint']['line-width'], .6);
        expect(layer['paint']['line-color'], '#F0F0F0');
        expect(
          layer['filter'],
          contains(
            equals([
              '==',
              ['get', 'admin_level'],
              0,
            ]),
          ),
        );
      }
      final ocean = layers.singleWhere((l) => l['id'] == 'nowave-earth-ocean');
      expect(ocean['source-layer'], 'water');
      expect(ocean['source'], GlobeStyle.waterSource);
    },
  );

  test(
    'raster gaps use neutral water from Z5 without changing globe or land',
    () {
      final document = GlobeStyle.document(Uri.parse('file:///globe/'));
      final ocean = (document['layers'] as List).singleWhere(
        (layer) => layer['id'] == 'nowave-earth-ocean',
      );
      // The raster is composed above this existing vector water surface.
      // No additional source, mask dilation or interpolated depth is needed.
      expect(ocean['slot'], 'bottom');
      expect(ocean['source-layer'], 'water');
      expect(ocean['paint']['fill-color'], [
        'step',
        ['zoom'],
        MarinePalette.water,
        MarineZoom.raster,
        MarinePalette.unmappedWater,
      ]);
      expect(ocean['paint']['fill-opacity'], 1);
      expect(MarinePalette.water, '#002D51');
      expect(MarinePalette.unmappedWater, '#93ACB0');
      final base = (document['imports'] as List).single;
      expect(base['config']['colorWater'], MarinePalette.water);
      expect(base['config']['colorLand'], LandColors.color('#C4AD80'));
      expect((document['sources'] as Map).length, 2);
    },
  );

  test(
    'atmosphère cyan native : interpolation continue et espace conservé',
    () {
      final document = jsonDecode(
        jsonEncode(GlobeStyle.document(Uri.parse('file:///globe/'))),
      ) as Map;
      final fog = document['fog'] as Map;
      expect(fog['color'], '#84D6F2');
      expect(fog['high-color'], 'rgba(40, 145, 210, 0.70)');
      expect(fog['space-color'], 'rgba(1, 3, 11, 0)');
      expect(fog['range'], [.8, 8]);
      expect(fog['horizon-blend'], [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        .010,
        4,
        .006,
        7,
        .003,
      ]);
      expect(fog['star-intensity'], 0);
      final stops = fog['horizon-blend'] as List;
      for (var index = 3; index < stops.length; index += 2) {
        expect(stops[index + 1], inInclusiveRange(0, 1));
        if (index > 3) expect(stops[index], greaterThan(stops[index - 2]));
      }
      expect(
        (document['layers'] as List).any((layer) => layer['type'] == 'sky'),
        false,
      );
    },
  );

  test('bundle exports the same vector style without image assets', () async {
    final uri = await GlobeStyle.prepare();
    final style =
        jsonDecode(await File.fromUri(Uri.parse(uri)).readAsString()) as Map;
    expect(style, GlobeStyle.document(Uri.parse(uri).resolve('.')));
    expect(
      (style['sources'] as Map).values.every((s) => s['type'] == 'vector'),
      isTrue,
    );
  });

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
      final labelCalls = map.style.calls.where(
        (c) => c.containsKey('showPlaceLabels'),
      );
      expect(labelCalls.map((c) => c['showPlaceLabels']), [false, true, false]);
      presentation.styleLoaded();
      await presentation.synchronize(map, .65);
      expect(labelCalls.length, 4);
      map.style.fail = true;
      await presentation.synchronize(map, 6);
      map.style.fail = false;
      await presentation.synchronize(map, 6);
      expect(map.style.config['showPlaceLabels'], true);
      expect(map.style.config.containsKey('showAdminBoundaries'), isFalse);
    },
  );

  test(
    'globe updates preserve marine water colour, theme and lighting',
    () async {
      final map = _Map();
      final marine = MarineMapController(bathymetryTilesUrl: '');
      final presentation = GlobePresentation();
      // Exercise both style-load operations together, as on the actual screen.
      await Future.wait([
        marine.install(map),
        presentation.synchronize(map, GlobeStyle.initialZoom),
      ]);
      for (final reload in [false, true]) {
        if (reload) {
          map.style.config
            ..clear()
            ..addAll({'lightPreset': 'day', 'theme': 'faded'});
          presentation.styleLoaded();
          await marine.install(map);
        }
        for (final zoom in [0.65, 5.9, 6.0, 12.0, 17.0, 3.0]) {
          await presentation.synchronize(map, zoom);
          expect(
            map.style.config['colorWater'],
            MarineMapController.deepWaterColor,
          );
          expect(map.style.config['lightPreset'], 'day');
          expect(map.style.config['theme'], 'faded');
          expect(map.style.config['colorLand'], LandColors.color('#C4AD80'));
          expect(
            map.style.config['colorGreenspace'],
            LandColors.color('#627545'),
          );
          expect(map.style.config['showRoadLabels'], false);
          expect(map.style.config['showPointOfInterestLabels'], false);
          expect(map.style.config['showPlaceLabels'], zoom >= 4);
          expect(map.style.config['showAdminBoundaries'], false);
        }
      }
    },
  );
}
