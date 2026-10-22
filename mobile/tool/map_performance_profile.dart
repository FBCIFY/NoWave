// Profile-only controlled workload using the real MapScreen and Mapbox renderer.
// No Firebase session, report creation, OS location override or production API.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:blueway/core/api/api_config.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/map/map_config.dart';
import 'package:blueway/core/map/map_performance.dart';
import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

final _headings = _Headings();
Timer? _headingTimer;
var _mode = 'normal';
final _payloads = <String, List<int>>{};

List<int> _features(String family) => utf8.encode(
  jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (var i = 0; i < (family == 'soundings' ? 900 : 300); i++)
        {
          'type': 'Feature',
          'id': 'diagnostic-$family-$i',
          'geometry': family == 'depth-contours'
              ? {
                  'type': 'LineString',
                  'coordinates': [
                    for (var j = 0; j < 24; j++)
                      [5.92 + j * .0008, 43.075 + i * .00006],
                  ],
                }
              : {
                  'type': 'Point',
                  'coordinates': [
                    5.92 + (i % 30) * .001,
                    43.075 + (i ~/ 30) * .001,
                  ],
                },
          'properties': {
            'name': 'Diagnostic $i',
            'category': 'harbour',
            'type': 'buoy_lateral',
            'color': 'red',
            'colour': ['red'],
            'colour_pattern': '',
            'shape': 'can',
            'value_m': i + 1,
            'depth_label': '${i + 1}',
            'contour_class': i.isEven ? 'major' : 'minor',
            'nature': 'point_sounding',
            'display_minzoom': 13,
          },
        },
    ],
  }),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kProfileMode || !MapPerformance.enabled) {
    throw StateError('Use --profile --dart-define=NOWAVE_MAP_PROFILE=true.');
  }
  if (ApiConfig.marineBaseUrl != 'http://127.0.0.1:18097') {
    throw StateError('Use the controlled local marine base on port18097.');
  }
  final picture = ui.PictureRecorder();
  ui.Canvas(picture); // A full-size transparent raster, not a fake depth map.
  final recording = picture.endRecording();
  final image = await recording.toImage(256, 256);
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  recording.dispose();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18097);
  server.listen((request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    if (request.uri.path.contains('/marine-features/')) {
      if (_mode == 'offline') {
        response.statusCode = 503;
      } else {
        if (_mode == 'slow') {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        final family = request.uri.pathSegments[4];
        response.headers.contentType = ContentType('application', 'geo+json');
        response.headers.set(
          'X-NoWave-Marine-Status',
          _mode == 'partial' ? 'partial' : 'ok',
        );
        response.add(_payloads.putIfAbsent(family, () => _features(family)));
      }
    } else if (request.uri.path.endsWith('.png')) {
      response.headers.contentType = ContentType('image', 'png');
      response.add(png);
    } else {
      response.headers.contentType = ContentType('application', 'x-protobuf');
    }
    await response.close();
  });
  developer.registerExtension('ext.nowave.profileInput', (_, args) async {
    _headingTimer?.cancel();
    _headingTimer = null;
    if (args['headings'] == 'rotate' || args['headings'] == 'fixed') {
      var heading = 1.0;
      _headingTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        if (args['headings'] == 'rotate') heading = (heading + 2) % 360;
        _headings.values.add(heading);
      });
    }
    _mode = args['network'] ?? _mode;
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'network': _mode}),
    );
  });
  MapboxOptions.setAccessToken(MapConfig.accessToken);
  await MapConfig.prepareStyle();
  runApp(
    MaterialApp(
      home: MapScreen(
        locationService: _NoLocation(),
        orientationService: _headings,
      ),
    ),
  );
}

class _Headings extends DeviceOrientationService {
  final values = StreamController<double>.broadcast(sync: true);
  @override
  Stream<double> get mapHeadings => values.stream;
}

class _NoLocation extends LocationService {
  @override
  Future<void> requestPermission() async =>
      throw StateError('Diagnostic sans GPS.');
  @override
  Future<geo.Position> getCurrentPosition() async =>
      throw StateError('Diagnostic sans GPS.');
  @override
  Future<bool> canWatchPosition() async => false;
  @override
  Stream<geo.Position> watchPosition() => const Stream.empty();
}
