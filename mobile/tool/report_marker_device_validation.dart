// Native Android Release fixture. No Firebase account, production report reads
// or writes, and no public marine provider requests. Mapbox rendering is real.
// flutter run --release -t tool/report_marker_device_validation.dart
// --dart-define-from-file=<private .env.json>
// --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:18098
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blueway/core/api/api_config.dart';
import 'package:blueway/core/location/location_service.dart';
import 'package:blueway/core/map/map_config.dart';
import 'package:blueway/features/map/data/report_tiles.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:blueway/features/map/presentation/report_marker.dart' as badges;
import 'package:blueway/features/reports/data/report_detail_service.dart';
import 'package:blueway/features/reports/domain/manual_report.dart';
import 'package:blueway/features/reports/domain/report_detail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void evidence(String event, [Map<String, Object?> values = const {}]) {
  // ignore: avoid_print
  print('NATIVE_MARKER_VALIDATION ${jsonEncode({'event': event, ...values})}');
}

ReportDetail fixture(ReportCategory category) => ReportDetail(
  id: 'native-fixture-${category.apiValue}',
  category: category,
  description: 'Fixture locale Android — aucun danger publié',
  latitude: 43.1,
  longitude: 5.93 + (category.index - 1) * .2,
  observedAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 2)),
  author: null,
  boat: null,
  photo: null,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode || ApiConfig.marineBaseUrl != 'http://127.0.0.1:18098') {
    throw StateError('Use Release and the isolated loopback marine URL.');
  }
  // Optional marine layers are empty fixtures, never production data. Android
  // may reject cleartext in Release; that does not validate marine networking.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18098);
  server.listen((request) async {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  });
  MapboxOptions.setAccessToken(MapConfig.accessToken);
  await MapConfig.prepareStyle();
  runApp(const MaterialApp(home: _Validation()));
}

class _NoGps extends LocationService {
  @override
  Future<geo.Position> getCurrentPosition() async =>
      throw StateError('Fixture locale sans GPS');
  @override
  Future<bool> canWatchPosition() async => false;
}

class _Details implements ReportDetailService {
  @override
  Future<ReportDetail> fetchReport(String id) async {
    final report = ReportCategory.values
        .map(fixture)
        .firstWhere((r) => r.id == id);
    evidence('detail_open', {'category': report.category.apiValue});
    return report;
  }

  @override
  Future<Uint8List> fetchPhoto(String url) async => Uint8List(0);
}

class _Tiles implements ReportTiles {
  final ready = Completer<MapboxMap>();
  int installations = 0;

  @override
  Future<void> authorize(MapboxMap map) async {}

  @override
  Future<void> addTo(MapboxMap map) async {
    final style = map.style;
    for (final category in ReportCategory.values) {
      final side = (badges.ReportMarker.size * badges.ReportMarker.pixelRatio)
          .round();
      await style.addStyleImage(
        badges.ReportMarker.imageId(category),
        badges.ReportMarker.pixelRatio,
        MbxImage(
          width: side,
          height: side,
          data: await badges.ReportMarker.paintCategory(category),
        ),
        false,
        [],
        [],
        null,
      );
      if (!await style.hasStyleImage(badges.ReportMarker.imageId(category))) {
        throw StateError('Native image missing: ${category.apiValue}');
      }
    }
    if (!await style.styleSourceExists(ReportTiles.sourceId)) {
      await style.addSource(
        GeoJsonSource(
          id: ReportTiles.sourceId,
          data: jsonEncode({
            'type': 'FeatureCollection',
            'features': [
              for (final category in ReportCategory.values)
                {
                  'type': 'Feature',
                  'properties': {
                    'report_id': fixture(category).id,
                    'category': category.apiValue,
                  },
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [fixture(category).longitude, 43.1],
                  },
                },
            ],
          }),
        ),
      );
    }
    if (!await style.styleLayerExists(ReportTiles.pointsLayerId)) {
      await style.addLayer(
        SymbolLayer(
          id: ReportTiles.pointsLayerId,
          sourceId: ReportTiles.sourceId,
          minZoom: 9,
          iconImageExpression: ReportTiles.markerImageExpression(),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconEmissiveStrength: 1,
        ),
      );
    }
    // Controlled grouped feature below Z9; real backend clustering is covered
    // by backend tests, not asserted by this native image fixture.
    if (!await style.styleLayerExists('fixture-group')) {
      await style.addLayer(
        CircleLayer(
          id: 'fixture-group',
          sourceId: ReportTiles.sourceId,
          maxZoom: 9,
          circleRadius: 12,
          circleColor: 0xFFED9D24,
        ),
      );
    }
    installations++;
    evidence('images_installed', {
      'count': ReportCategory.values.length,
      'installation': installations,
      'mode': 'release',
      'source': 'local_geojson_fixture',
    });
    if (!ready.isCompleted) ready.complete(map);
  }
}

class _Validation extends StatefulWidget {
  const _Validation();
  @override
  State<_Validation> createState() => _ValidationState();
}

class _ValidationState extends State<_Validation> with WidgetsBindingObserver {
  final _tiles = _Tiles();
  final _focus = MapFocusController();
  String _status = 'Recette native Release — fixtures locales';
  MapboxMap? _map;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  Future<List<QueriedRenderedFeature?>> _features(String layer) async =>
      _map!.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: 0, y: 0),
            max: ScreenCoordinate(
              x: (await _map!.getSize()).width,
              y: (await _map!.getSize()).height,
            ),
          ),
        ),
        RenderedQueryOptions(layerIds: [layer]),
      );

  Future<void> _camera(double zoom, [double longitude = 5.93]) async {
    await _map!.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(longitude, 43.1)),
        zoom: zoom,
        pitch: 0,
        bearing: 0,
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  Future<void> _run() async {
    try {
      _map = await _tiles.ready.future.timeout(const Duration(seconds: 60));
      await _camera(8);
      if ((await _features(ReportTiles.pointsLayerId)).isNotEmpty) {
        throw StateError('Badges visible below Z9');
      }
      evidence('below_z9_hidden');
      await _camera(9);
      final categories = (await _features(ReportTiles.pointsLayerId))
          .whereType<QueriedRenderedFeature>()
          .map(
            (f) => (f.queriedFeature.feature['properties'] as Map)['category'],
          )
          .toSet();
      if (categories.length != ReportCategory.values.length) {
        throw StateError('Missing rendered categories at Z9: $categories');
      }
      evidence('z9_categories_rendered', {'categories': categories.toList()});
      await _camera(12);
      await _camera(10, 6.03);
      await _camera(9);
      evidence('zoom_and_pan');
      _focus.focus(fixture(ReportCategory.obstruction));
      await Future<void>.delayed(const Duration(seconds: 3));
      if ((await _features('alert-selected-point')).isEmpty) {
        throw StateError('Selected marker missing');
      }
      evidence('selected_marker_rendered');
      final previous = _tiles.installations;
      await _map!.loadStyleURI(MapConfig.styleUrl);
      for (var i = 0; i < 30 && _tiles.installations == previous; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      if (_tiles.installations == previous ||
          (await _features('alert-selected-point')).isEmpty) {
        throw StateError('Style reload did not restore images and selection');
      }
      evidence('style_reload');
      // End with a large selected badge in the centre for an actual ADB tap.
      await _camera(12);
      _finished = true;
      if (mounted) {
        setState(
          () => _status =
              'PASS auto — toucher le badge central, puis arrière-plan/retour',
        );
      }
      evidence('automatic_pass');
    } catch (error) {
      evidence('fail', {'error': error.toString()});
      if (mounted) setState(() => _status = 'FAIL : $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    evidence('lifecycle', {'state': state.name});
    if (_finished && state == AppLifecycleState.resumed) {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3), () async {
          evidence('resume_check', {
            'selected_visible': (await _features('alert-selected-point'))
                .isNotEmpty,
          });
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      MapScreen(
        focusController: _focus,
        reportTiles: _tiles,
        reportDetailService: _Details(),
        locationService: _NoGps(),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 80,
        child: IgnorePointer(
          child: Material(
            color: Colors.white.withValues(alpha: .9),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_status),
            ),
          ),
        ),
      ),
    ],
  );
}
