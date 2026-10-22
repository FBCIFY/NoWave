import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/map/map_config.dart';
import 'marine_viewport.dart';

/// VM-service-only diagnostics in the real application. No authentication,
/// account mutation, location simulation or public network control endpoint.
abstract final class MarineDebug {
  static bool _registered = false;
  static MapboxMap? _map;
  static MarineViewport? _viewport;
  static Future<void> Function(CameraOptions)? _camera;

  static void attach({
    required MapboxMap map,
    required MarineViewport viewport,
    required Future<void> Function(CameraOptions) camera,
  }) {
    if (!kDebugMode) return;
    _map = map;
    _viewport = viewport;
    _camera = camera;
    if (_registered) return;
    _registered = true;
    developer.registerExtension('ext.nowave.marine', (_, args) async {
      try {
        final map = _map!;
        final viewport = _viewport!;
        if (args['action'] == 'camera') {
          await _camera!(
            CameraOptions(
              center: Point(
                coordinates: Position(
                  double.parse(args['lon']!),
                  double.parse(args['lat']!),
                ),
              ),
              zoom: double.parse(args['zoom']!),
              bearing: double.tryParse(args['bearing'] ?? '') ?? 0,
              pitch: double.tryParse(args['pitch'] ?? '') ?? 0,
            ),
          );
        } else if (args['action'] == 'reload') {
          await map.loadStyleURI(MapConfig.styleUrl);
        } else if (args['action'] == 'sync') {
          await viewport.synchronize(map);
        } else if (args['action'] == 'snapshot') {
          return developer.ServiceExtensionResponse.result(
            jsonEncode({'png': base64Encode(await map.snapshot())}),
          );
        } else if (args['action'] == 'style') {
          final images = <String, Object?>{};
          final imageIds = args['images'] == null
              ? <String>[
                  'nowave-buoy-green',
                  'nowave-buoy-red',
                  'nowave-buoy-north',
                  'nowave-beacon-green',
                  'nowave-lighthouse-white',
                ]
              : (jsonDecode(args['images']!) as List).cast<String>();
          for (final id in imageIds) {
            final image = await map.style.getStyleImage(id);
            images[id] = image == null
                ? null
                : {'width': image.width, 'height': image.height};
          }
          // getStyleJSON may retain the originally loaded document. Read the
          // runtime objects too, including dynamically installed marine layers.
          final layers = <String, Object?>{};
          for (final info in await map.style.getStyleLayers()) {
            if (info == null || !info.id.startsWith('nowave-')) continue;
            layers[info.id] = jsonDecode(
              await map.style.getStyleLayerProperties(info.id),
            );
          }
          final sources = <String, Object?>{};
          for (final id in [
            'nowave-bathymetry',
            ...MarineViewport.sources.values,
          ]) {
            sources[id] = await map.style.styleSourceExists(id)
                ? jsonDecode(await map.style.getStyleSourceProperties(id))
                : null;
          }
          return developer.ServiceExtensionResponse.result(
            jsonEncode({
              'style': jsonDecode(await map.style.getStyleJSON()),
              'runtimeLayers': layers,
              'runtimeSources': sources,
              'images': images,
              'marineBaseUrl': viewport.apiBaseUrl,
            }),
          );
        }
        final camera = await map.getCameraState();
        final size = viewport.viewportSize();
        final rendered = await map.queryRenderedFeatures(
          RenderedQueryGeometry.fromScreenBox(
            ScreenBox(
              min: ScreenCoordinate(x: 0, y: 0),
              max: ScreenCoordinate(x: size.width, y: size.height),
            ),
          ),
          RenderedQueryOptions(
            layerIds: [
              'nowave-harbour-icons',
              'nowave-buoy-symbols',
              'nowave-buoy-safety',
              'nowave-beacons-unqualified',
              'nowave-beacons-local',
              'nowave-beacons-main',
              'nowave-lights-local',
              'nowave-lights-major',
              'nowave-lighthouses',
              'nowave-hazard-points',
              'nowave-depth-major',
              'nowave-depth-minor',
              'nowave-depth-labels',
              'nowave-depth-soundings',
            ],
          ),
        );
        final projected = <Map<String, Object?>>[];
        if (args['project'] == 'true') {
          final points = [
            for (final family in ['harbours', 'seamarks'])
              for (final f in viewport.features(family))
                if (f['geometry']['type'] == 'Point') f,
          ];
          final pixels = await map.pixelsForCoordinates([
            for (final f in points)
              Point(
                coordinates: Position.fromJson(
                  (f['geometry']['coordinates'] as List).cast<num>(),
                ),
              ),
          ]);
          for (var i = 0; i < points.length; i++) {
            projected.add({
              'id': points[i]['id'],
              'type': points[i]['properties']['type'],
              'category': points[i]['properties']['category'],
              'x': pixels[i]?.x,
              'y': pixels[i]?.y,
            });
          }
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode({
            'camera': {
              'zoom': camera.zoom,
              'lon': camera.center.coordinates.lng,
              'lat': camera.center.coordinates.lat,
              'bearing': camera.bearing,
              'pitch': camera.pitch,
            },
            'size': {'width': size.width, 'height': size.height},
            if (args['project'] == 'true') 'projected': projected,
            'metrics': viewport.metrics,
            'rendered': [
              for (final f in rendered)
                if (f != null)
                  {'layers': f.layers, 'feature': f.queriedFeature.feature},
            ],
            'data': {
              for (final family in MarineViewport.sources.keys)
                family: viewport.features(family),
            },
          }),
        );
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          e.toString(),
        );
      }
    });
  }
}
