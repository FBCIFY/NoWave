// Native-map diagnostic only. No Firebase login, report creation or device
// position upload. Run with flutter run --profile -t tool/map_motion_probe.dart
// --dart-define-from-file=.env.json -d <device>.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:blueway/core/map/map_config.dart';
import 'package:blueway/core/map/map_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kProfileMode) throw StateError('Use --profile for this diagnostic.');
  mb.MapboxOptions.setAccessToken(MapConfig.accessToken);
  await MapConfig.prepareStyle();
  runApp(const MaterialApp(home: _Probe()));
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static const channel = MethodChannel('fr.blueway.app/map_motion');
  mb.MapboxMap? _map;
  bool _started = false;
  bool _collect = false;
  bool _baseline = false;
  String _status = 'Préparation du diagnostic…';
  final _results = <Map<String, Object?>>[];
  Object? _poles;
  final _clock = Stopwatch();
  final _flutterFrames = <ui.FrameTiming>[];
  final _nativeRenderUs = <int>[];
  final _pointers = <int>{};
  int? _firstCameraUs, _releaseUs;
  int _lastCameraUs = 0;
  double? _targetZoom;
  Completer<void>? _settled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_frames);
  }

  void _frames(List<ui.FrameTiming> frames) {
    if (_collect) _flutterFrames.addAll(frames);
  }

  void _begin() {
    _firstCameraUs = null;
    _releaseUs = null;
    _lastCameraUs = 0;
    _flutterFrames.clear();
    _nativeRenderUs.clear();
    _clock
      ..reset()
      ..start();
    _collect = true;
  }

  Map<String, Object?> _measure(String scenario) {
    final native = [..._nativeRenderUs]..sort();
    final ui =
        _flutterFrames.map((f) => f.buildDuration.inMicroseconds).toList()
          ..sort();
    final raster =
        _flutterFrames.map((f) => f.rasterDuration.inMicroseconds).toList()
          ..sort();
    int? p95(List<int> samples) =>
        samples.isEmpty ? null : samples[((samples.length - 1) * .95).round()];
    final budget = 1000000 / View.of(context).display.refreshRate;
    return {
      'scenario': scenario,
      'mode': _baseline ? 'baseline' : 'improved',
      'revision': const String.fromEnvironment('MAP_PROBE_REVISION'),
      'camera_command_or_pointer_to_first_event_ms':
          (_firstCameraUs ?? 0) / 1000,
      'last_camera_event_ms': _lastCameraUs / 1000,
      'release_to_last_camera_event_ms': _releaseUs == null
          ? null
          : ((_lastCameraUs - _releaseUs!).clamp(0, 10000000)) / 1000,
      'native_frames': native.length,
      'native_render_p95_us': p95(native),
      'flutter_frames': ui.length,
      'flutter_ui_p95_us': p95(ui),
      'flutter_raster_p95_us': p95(raster),
      'flutter_frames_over_budget': _flutterFrames
          .where(
            (f) =>
                f.buildDuration.inMicroseconds > budget ||
                f.rasterDuration.inMicroseconds > budget,
          )
          .length,
      'refresh_hz': View.of(context).display.refreshRate,
    };
  }

  Future<void> _save(Map<String, Object?> result) async {
    _results.add(result);
    // ignore: avoid_print
    print('MAP_MOTION_PROBE ${jsonEncode(result)}');
    await File('${Directory.systemTemp.path}/nowave-map-motion-probe.json')
        .writeAsString(jsonEncode({'poles': _poles, 'measurements': _results}));
  }

  Future<void> _run() async {
    if (_started || _map == null) return;
    _started = true;
    final map = _map!;
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      _poles = await channel.invokeMethod<Object>('diagnosePoles');
      if (_poles is List) {
        for (final trial in _poles! as List) {
          final samples =
              (trial['drag_samples'] as List)
                  .map((p) => (p[1] as num).toDouble())
                  .toList()
                ..sort();
          // ignore: avoid_print
          print(
            'MAP_POLE_PROBE ${jsonEncode({'hemisphere': trial['hemisphere'], 'requested_latitude': trial['requested_latitude'], 'actual_latitude': trial['actual_latitude'], 'drag_min_latitude': samples.first, 'drag_max_latitude': samples.last})}',
          );
        }
      }
      for (var trial = 1; trial <= 3; trial++) {
        for (final duration in [500, MapMotion.clusterDurationMs]) {
          if (!mounted) return;
          setState(() => _status = 'Zoom natif : essai $trial/3, $duration ms');
          await map.setCamera(
            mb.CameraOptions(
              center: mb.Point(coordinates: mb.Position(5.37, 43.29)),
              zoom: 6,
              bearing: 0,
              pitch: 0,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 700));
          _targetZoom = 8;
          _settled = Completer<void>();
          _begin();
          await map.easeTo(
            mb.CameraOptions(zoom: 8),
            mb.MapAnimationOptions(duration: duration),
          );
          var complete = true;
          try {
            await _settled!.future.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            complete = false;
            await map.cancelCameraAnimation();
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
          _collect = false;
          await _save({
            ..._measure('programmatic_cluster_zoom'),
            'trial': trial,
            'requested_duration_ms': duration,
            'input': 'scripted_camera_command',
            'complete': complete,
          });
          _targetZoom = null;
        }
      }
      await map.setCamera(mb.CameraOptions(zoom: .65, bearing: 0, pitch: 0));
      await _configure(false);
      if (mounted) {
        setState(
          () => _status = 'Glisse le globe ou pince pour mesurer les gestes.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Diagnostic interrompu : $error');
      // ignore: avoid_print
      print('MAP_MOTION_PROBE_ERROR $error');
    }
  }

  Future<void> _configure(bool baseline) async {
    final map = _map;
    if (map == null) return;
    if (baseline) {
      await map.gestures.updateSettings(
        mb.GesturesSettings(
          scrollDecelerationEnabled: true,
          pinchToZoomDecelerationEnabled: true,
          rotateDecelerationEnabled: true,
        ),
      );
      await channel.invokeMethod<bool>('configure', {
        'baseline': true,
        'iosDecay': .998,
      });
    } else {
      await MapMotion.configure(map, reduceMotion: false);
    }
    if (mounted) setState(() => _baseline = baseline);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) {
                if (_targetZoom != null) return;
                if (_pointers.isEmpty) _begin();
                _pointers.add(event.pointer);
              },
              onPointerUp: (event) {
                _pointers.remove(event.pointer);
                if (_pointers.isEmpty) _releaseUs = _clock.elapsedMicroseconds;
              },
              onPointerCancel: (event) {
                _pointers.remove(event.pointer);
                _collect = false;
              },
              child: mb.MapWidget(
                mapOptions: mb.MapOptions(
                  constrainMode: mb.ConstrainMode.NONE,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
                viewport: const mb.IdleViewportState(),
                styleUri: MapConfig.styleUrl,
                onMapCreated: (map) => _map = map,
                onStyleLoadedListener: (_) => unawaited(_run()),
                onCameraChangeListener: (event) {
                  if (!_collect) return;
                  _firstCameraUs ??= _clock.elapsedMicroseconds;
                  _lastCameraUs = _clock.elapsedMicroseconds;
                  if (_targetZoom != null &&
                      (event.cameraState.zoom - _targetZoom!).abs() < .0001) {
                    if (!(_settled?.isCompleted ?? true)) _settled!.complete();
                  }
                },
                onRenderFrameFinishedListener: (event) {
                  if (_collect) {
                    _nativeRenderUs.add(
                      event.timeInterval.end
                          .difference(event.timeInterval.begin)
                          .inMicroseconds,
                    );
                  }
                },
                onMapIdleListener: (_) {
                  if (_collect && _targetZoom == null && _releaseUs != null) {
                    _collect = false;
                    unawaited(
                      _save({
                        ..._measure('manual_gesture'),
                        'input': 'physical_touch',
                      }),
                    );
                  }
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_status),
                      if (_targetZoom == null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => unawaited(_configure(true)),
                              child: Text(
                                _baseline ? '● Référence' : 'Référence',
                              ),
                            ),
                            TextButton(
                              onPressed: () => unawaited(_configure(false)),
                              child: Text(
                                !_baseline ? '● Amélioré' : 'Amélioré',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_frames);
    super.dispose();
  }
}
