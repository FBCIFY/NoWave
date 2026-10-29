// Pinned SDK 2.30.1 hosting-mode experiment, opt-in diagnostics only.
// ignore_for_file: experimental_member_use
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Explicit local diagnostics; eliminated from release builds. No map, account,
/// token or location is retained. Samples are bounded and never logged per frame.
abstract final class MapPerformance {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('NOWAVE_MAP_PROFILE');
  static const hostingMode =
      enabled && String.fromEnvironment('NOWAVE_MAP_HOSTING') == 'TLHC'
      ? AndroidPlatformViewHostingMode.TLHC_VD
      : AndroidPlatformViewHostingMode.VD;
  static bool _registered = false, _installed = false, _collect = false;
  static int _generation = 0;
  static int nativeMapsCreated = 0;
  static final _counts = <String, int>{};
  static final _samples = <String, List<int>>{};
  static final _ui = <int>[], _raster = <int>[], _native = <int>[];
  static const _limit = 12000;

  static void initialize() {
    if (!enabled) return;
    if (!_installed) {
      SchedulerBinding.instance.addTimingsCallback(_frames);
      _installed = true;
    }
    if (_registered) return;
    _registered = true;
    developer.registerExtension('ext.nowave.performance', (_, args) async {
      if (args['action'] == 'begin') {
        _generation++;
        _counts.clear();
        _samples.clear();
        _ui.clear();
        _raster.clear();
        _native.clear();
        _collect = true;
      } else if (args['action'] == 'end') {
        _collect = false;
      }
      return developer.ServiceExtensionResponse.result(jsonEncode(snapshot()));
    });
  }

  static void detach() {
    if (!enabled) return;
    _collect = false;
    _generation++;
    if (_installed) SchedulerBinding.instance.removeTimingsCallback(_frames);
    _installed = false;
  }

  static void count(String name) {
    if (enabled && _collect) {
      _counts.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  static ({int generation, Stopwatch clock})? begin() => enabled && _collect
      ? (generation: _generation, clock: Stopwatch()..start())
      : null;

  static void finish(String name, ({int generation, Stopwatch clock})? span) {
    if (span == null || !_collect || span.generation != _generation) return;
    count(name);
    final samples = _samples.putIfAbsent(name, () => []);
    if (samples.length < _limit) samples.add(span.clock.elapsedMicroseconds);
  }

  static void _frames(List<ui.FrameTiming> frames) {
    if (!_collect) return;
    for (final frame in frames) {
      if (_ui.length >= _limit) break;
      _ui.add(frame.buildDuration.inMicroseconds);
      _raster.add(frame.rasterDuration.inMicroseconds);
    }
  }

  static void nativeFrame(RenderFrameFinishedEventData frame) {
    if (_collect && _native.length < _limit) {
      _native.add(
        frame.timeInterval.end
            .difference(frame.timeInterval.begin)
            .inMicroseconds,
      );
    }
  }

  static Map<String, Object?> _distribution(List<int> input) {
    final sorted = [...input]..sort();
    return {
      'samples': sorted.length,
      'p50_us': sorted.isEmpty ? null : sorted[(sorted.length - 1) ~/ 2],
      'p95_us': sorted.isEmpty
          ? null
          : sorted[((sorted.length - 1) * .95).round()],
      'total_us': sorted.fold<int>(0, (a, b) => a + b),
    };
  }

  static Map<String, Object?> snapshot() {
    final hz = ui.PlatformDispatcher.instance.views.first.display.refreshRate;
    final budget = 1000000 / hz;
    return {
      'refresh_hz': hz,
      'hosting_mode': hostingMode.name,
      'budget_us': budget,
      'native_maps_created': nativeMapsCreated,
      'counts': Map<String, int>.of(_counts),
      'operations': {
        for (final e in _samples.entries) e.key: _distribution(e.value),
      },
      'flutter_ui': _distribution(_ui),
      'flutter_raster': _distribution(_raster),
      'mapbox_render': _distribution(_native),
      'flutter_over_budget': [
        for (var i = 0; i < _ui.length; i++)
          if (_ui[i] > budget || _raster[i] > budget) i,
      ].length,
      'sample_limit': _limit,
    };
  }
}
