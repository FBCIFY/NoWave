// Diagnostic uniquement : flutter run --profile -t tool/compass_device_profile.dart
// --dart-define-from-file=.env.json -d <device>
// Aucun compte Firebase, signalement ou envoi de position au backend.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:blueway/core/api/api_config.dart';
import 'package:blueway/core/map/map_config.dart';
import 'package:blueway/core/sensors/device_orientation_service.dart';
import 'package:blueway/features/map/presentation/map_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kProfileMode) throw StateError('Exécuter ce diagnostic avec --profile.');
  const localMarine = 'http://127.0.0.1:18097';
  if (ApiConfig.marineBaseUrl != localMarine) {
    throw StateError('Ajouter --dart-define=MARINE_API_BASE_URL=$localMarine');
  }
  // Couche marine vide et déterministe : ne solliciter aucun backend réel.
  // La carte Mapbox et son rendu natif restent réels.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18097);
  final transparent = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  server.listen((request) async {
    request.response.headers.set('Cache-Control', 'public, max-age=86400');
    final png = request.uri.path.endsWith('.png');
    request.response.headers.set(
      'Content-Type',
      png ? 'image/png' : 'application/x-protobuf',
    );
    request.response.add(png ? transparent : <int>[]);
    await request.response.close();
  });
  MapboxOptions.setAccessToken(MapConfig.accessToken);
  await MapConfig.prepareStyle();
  runApp(const MaterialApp(home: _Profile()));
}

class _Headings extends DeviceOrientationService {
  final values = StreamController<double>.broadcast(sync: true);
  @override
  Stream<double> get mapHeadings => values.stream;
}

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  final _headings = _Headings();
  final _frames = <FrameTiming>[];
  Timer? _emitter;
  bool _collect = false;
  bool _cancelled = false;
  String _status = 'Préparation de la carte (15 s)…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    unawaited(_run());
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_collect) _frames.addAll(timings);
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 15));
    for (var trial = 1; trial <= 3 && !_cancelled; trial++) {
      for (final rotating in [false, true]) {
        if (_cancelled) return;
        setState(
          () => _status =
              'Essai $trial/3 : ${rotating ? "rotation" : "cap fixe"} (30 s)',
        );
        // Exclure la reconstruction de l'interface du diagnostic.
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_cancelled) return;
        _frames.clear();
        var emissions = 0;
        var heading = 1.0;
        final elapsed = Stopwatch()..start();
        _collect = true;
        _emitter = Timer.periodic(const Duration(milliseconds: 20), (_) {
          if (rotating) heading = (heading + 2) % 360;
          emissions++;
          _headings.values.add(heading);
        });
        await Future<void>.delayed(const Duration(seconds: 30));
        _emitter?.cancel();
        elapsed.stop();
        // Les timings sont livrés par lots ; attendre le dernier lot.
        await Future<void>.delayed(const Duration(seconds: 1));
        _collect = false;
        if (_cancelled || !mounted) return;
        final refreshRate = View.of(context).display.refreshRate;
        final budget = 1000000 / refreshRate;
        final ui = _frames.map((f) => f.buildDuration.inMicroseconds).toList()
          ..sort();
        final raster =
            _frames.map((f) => f.rasterDuration.inMicroseconds).toList()
              ..sort();
        int? percentile(List<int> samples, double p) => samples.isEmpty
            ? null
            : samples[((samples.length - 1) * p).round()];
        // ignore: avoid_print
        print(
          'COMPASS_DEVICE_PROFILE ${jsonEncode({'trial': trial, 'mode': rotating ? 'rotation' : 'stationary', 'input': 'synthetic_2_degrees_50hz', 'refresh_hz': refreshRate, 'emissions': emissions, 'elapsed_ms': elapsed.elapsedMilliseconds, 'frames': _frames.length, 'ui_median_us': percentile(ui, .5), 'ui_p95_us': percentile(ui, .95), 'raster_median_us': percentile(raster, .5), 'raster_p95_us': percentile(raster, .95), 'frames_over_budget': _frames.where((f) => f.buildDuration.inMicroseconds > budget || f.rasterDuration.inMicroseconds > budget).length})}',
        );
      }
    }
    if (mounted) {
      setState(() => _status = 'Terminé — résultats dans le journal Flutter.');
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _emitter?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    unawaited(_headings.values.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        MapScreen(orientationService: _headings),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_status),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
