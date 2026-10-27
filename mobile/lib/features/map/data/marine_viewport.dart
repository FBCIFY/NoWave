import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import '../../../core/map/map_performance.dart';
import '../../../core/map/marine/marine_zoom.dart';
import 'buoy_layer.dart';
import 'harbour_layer.dart';
import 'hydrography_layer.dart';
import 'marine_cell.dart';
import 'marine_mosaic.dart';

export 'marine_cell.dart' show MarineCell;

/// Stable representative placement. Collision eligibility is recalculated from
/// the current screen positions; retained ports precede all newcomers.
class HarbourSelection {
  final order = <String, int>{};
  int _sequence = 0;

  void reset() {
    order.clear();
    _sequence = 0;
  }

  List<Map<String, dynamic>> select(
    List<Map<String, dynamic>> features,
    List<ScreenCoordinate?> pixels,
    double zoom,
    double width,
    double height,
  ) {
    if (zoom < MarineZoom.harbours) {
      reset();
      return [];
    }
    final span = MapPerformance.begin();
    // A formerly selected port cannot keep priority after leaving the screen.
    const spacing = 24 * 1.12 + 6;
    final visibleIds = <String>{};
    for (var i = 0; i < features.length; i++) {
      final p = pixels[i];
      if (p != null &&
          p.x.isFinite &&
          p.y.isFinite &&
          p.x >= -spacing &&
          p.y >= -spacing &&
          p.x <= width + spacing &&
          p.y <= height + spacing) {
        visibleIds.add(features[i]['id'].toString());
      }
    }
    order.removeWhere((id, _) => !visibleIds.contains(id));
    final indexes = List.generate(features.length, (i) => i);
    int rank(Map<String, dynamic> f) {
      final p = f['properties'] as Map;
      return (p['name'] == '' ? 2 : 0) + (p['category'] == 'marina' ? 1 : 0);
    }

    indexes.sort((a, b) {
      final fa = features[a], fb = features[b];
      final ia = fa['id'].toString(), ib = fb['id'].toString();
      final oa = order[ia], ob = order[ib];
      if (oa != null || ob != null) {
        return (oa ?? 1 << 30).compareTo(ob ?? 1 << 30);
      }
      final r = rank(fa).compareTo(rank(fb));
      return r != 0 ? r : ia.compareTo(ib);
    });
    // Bucket only the collision search. Keep the original floating-point
    // predicate and priority order, including exact spacing boundaries.
    final occupied = <(int, int), List<ScreenCoordinate>>{};
    // For small inputs a short list is cheaper than nine bucket lookups.
    final linear = features.length < 128 ? <ScreenCoordinate>[] : null;
    final selected = <Map<String, dynamic>>[];
    // 24 logical px PNG at max icon size 1.12 plus six px padding.
    for (final i in indexes) {
      final p = pixels[i];
      final f = features[i];
      final id = f['id'].toString();
      if (p == null ||
          !p.x.isFinite ||
          !p.y.isFinite ||
          p.x < -spacing ||
          p.y < -spacing ||
          p.x > width + spacing ||
          p.y > height + spacing) {
        continue;
      }
      final x = (p.x / spacing).floor(), y = (p.y / spacing).floor();
      var collision =
          linear?.any(
            (q) => (q.x - p.x).abs() < spacing && (q.y - p.y).abs() < spacing,
          ) ??
          false;
      if (linear == null) {
        for (var dx = -1; dx <= 1 && !collision; dx++) {
          for (var dy = -1; dy <= 1 && !collision; dy++) {
            collision =
                occupied[(x + dx, y + dy)]?.any(
                  (q) =>
                      (q.x - p.x).abs() < spacing &&
                      (q.y - p.y).abs() < spacing,
                ) ??
                false;
          }
        }
      }
      if (collision) {
        continue;
      }
      order.putIfAbsent(id, () => _sequence++);
      if (linear == null) {
        occupied.putIfAbsent((x, y), () => []).add(p);
      } else {
        linear.add(p);
      }
      selected.add({
        ...f,
        'properties': {...f['properties'] as Map, 'selection_order': order[id]},
      });
    }
    MapPerformance.finish('ports_us', span);
    return selected;
  }
}

class _Snapshot {
  _Snapshot(
    this.family,
    this.cell,
    this.features,
    this.bytes,
    this.expires,
    this.complete,
  );
  final String family;
  final MarineCell cell;
  final List<Map<String, dynamic>> features;
  final int bytes;
  final DateTime expires;
  final bool complete;
}

/// Feature maps belong to read-only snapshots. Keep exact object references,
/// never an ID/hash signature: a replacement geometry must be encoded again.
class _EncodedCollection {
  _EncodedCollection(this.features, this.json);
  final List<Map<String, dynamic>> features;
  final String json;

  bool matches(List<Map<String, dynamic>> next) {
    if (features.length != next.length) return false;
    for (var i = 0; i < next.length; i++) {
      final a = features[i], b = next[i];
      if (identical(a, b)) continue;
      // Harbour placement adds a fresh properties wrapper. Compare every key,
      // including selection_order, while geometry identity remains exact.
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (key == 'properties' && a[key] is Map && b[key] is Map) {
          if (!mapEquals(a[key] as Map, b[key] as Map)) return false;
        } else if (a[key] != b[key]) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Public data only: two in-flight requests, lazy visible XYZ ranges,
/// 64 cached snapshots / 12 MiB encoded data. No Firebase headers or credentials.
/// Displayed geometry remains pinned until complete replacement coverage arrives;
/// contours keep their fixed Z12 ownership.
class MarineViewport {
  MarineViewport({
    required this.viewportSize,
    String? apiBaseUrl,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  }) : apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl,
       _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  final String apiBaseUrl;

  /// Logical pixels from Flutter layout; native getSize is unavailable on iOS.
  final ui.Size Function() viewportSize;
  final DateTime Function() _now;
  final http.Client Function() _clientFactory;
  final _cache = <String, _Snapshot>{};
  final _renderedData = <String, String>{};
  // One most recent encoding per source (five), sharing snapshot geometry.
  final _encodedCollections = <String, _EncodedCollection>{};
  int _encodings = 0;
  final selection = HarbourSelection();
  final _active = <String, http.Client>{};
  final _cancelledFlights = <String>{};
  final _failures = <String, DateTime>{};
  final _wanted = <String, (String, MarineCell)>{};
  // Full geographic demand is represented by ranges, not a world-sized list.
  // The bounded working set includes visible cells first, then their margin.
  final _ranges = <String, MarineCellRange>{};
  final _resolutionCaps = <String, int>{};
  final _budgetBlocked = <String>{};
  final _mosaics = <String, (int, List<Map<String, dynamic>>)>{};
  int _dataRevision = 0;
  int _plannedVisible = 0;
  double _longitude = 0, _latitude = 0;
  int? _requestCameraZoom;
  static const maxSnapshots = 64;
  static const maxEncodedBytes = 12 * 1024 * 1024;
  MarineCell? _useful;
  CoordinateBounds? _visibleBounds;
  final _visibilityRanges = <int, MarineCellRange>{};
  int _retainedBytes = 0;
  final _retainedSizes = <String, int>{};
  final _retainedPoints = <String, Map<String, dynamic>>{};
  Timer? _timer;
  Timer? _retryTimer;
  Future<void>? _drain;
  Future<void>? _rendering;
  bool _renderAgain = false;
  bool _pendingCamera = false;
  MapboxMap? _currentMap;
  MapboxMap? _scheduledMap;
  CameraState? _nextCamera;
  int _cameraGeneration = 0;
  double _currentZoom = 0;
  int _revision = 0;
  int _renderRevision = 0;
  int _bytes = 0;
  bool _busy = false, _again = false, _disposed = false, _paused = false;
  final _failureReasons = <String, String>{};
  int requests = 0, hits = 0, receivedBytes = 0, errors = 0, cancelled = 0;
  final _latencies = <int>[];
  Map<String, Object> get metrics => {
    'requests': requests,
    'cache_hits': hits,
    'received_bytes': receivedBytes,
    'errors': errors,
    'last_errors': Map<String, String>.of(_failureReasons),
    'cancelled': cancelled,
    'cache_entries': _cache.length,
    'cache_encoded_bytes': _bytes,
    'retained_encoded_bytes': _retainedBytes,
    'active': _active.length,
    'planned_visible': _plannedVisible,
    'wanted': _wanted.length,
    'budget_deferred': _budgetBlocked.length,
    'request_zooms': {for (final e in _ranges.entries) e.key: e.value.z},
    'encodings': _encodings,
    'busy': _busy,
    'latency_ms': List<int>.of(_latencies),
    'selected_harbours': selection.order.keys.toList(),
  };

  static const sources = {
    'harbours': HarbourLayer.sourceId,
    'seamarks': BuoyLayer.sourceId,
    'depth-contours': HydrographyLayer.contourSourceId,
    'soundings': HydrographyLayer.soundingSourceId,
    'underwater-hazards': HydrographyLayer.hazardSourceId,
  };

  void styleLoaded() {
    _renderRevision++;
    _renderedData.clear();
  }

  void schedule(
    MapboxMap map, {
    bool cameraChanged = false,
    CameraState? cameraState,
  }) {
    if (_disposed || _paused) return;
    _scheduledMap = map;
    _nextCamera = cameraState;
    _cameraGeneration++;
    _scheduleLatest(map);
  }

  void _scheduleLatest(MapboxMap map) {
    if (_disposed || _paused) return;
    // Start immediately, then coalesce frames into one update every 200 ms.
    // A change of bearing or pitch does not invalidate geographic requests.
    if (_timer == null) {
      unawaited(_synchronize(map));
      _timer = Timer(const Duration(milliseconds: 200), () {
        _timer = null;
        if (_pendingCamera && !_disposed && !_paused) {
          _pendingCamera = false;
          _scheduleLatest(_scheduledMap ?? map);
        }
      });
    } else {
      _pendingCamera = true;
    }
  }

  void resume(MapboxMap? map) {
    _paused = false;
    if (map != null) schedule(map);
  }

  void pause() {
    _paused = true;
    _again = false;
    _revision++;
    _renderRevision++;
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingCamera = false;
    _nextCamera = null;
    _cameraGeneration++;
    _wanted.clear();
    _budgetBlocked.clear();
    for (final entry in _active.entries) {
      _cancel(entry.key, entry.value);
    }
  }

  void _cancel(String key, http.Client client) {
    if (_cancelledFlights.add(key)) {
      client.close();
      cancelled++;
    }
  }

  void dispose() {
    _disposed = true;
    pause();
    _encodedCollections.clear();
  }

  Future<void> synchronize(MapboxMap map, {CameraState? cameraState}) {
    if (_disposed || _paused) return Future<void>.value();
    _scheduledMap = map;
    _nextCamera = cameraState;
    _cameraGeneration++;
    return _synchronize(map);
  }

  Future<void> _synchronize(MapboxMap requestedMap) async {
    if (_disposed || _paused) return;
    final map = _scheduledMap ?? requestedMap;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final revision = _revision;
    try {
      var cameraGeneration = _cameraGeneration;
      var camera = _nextCamera;
      if (camera == null) {
        MapPerformance.count('viewport_camera_reads');
        final cameraSpan = MapPerformance.begin();
        camera = await map.getCameraState();
        MapPerformance.finish('camera_read_us', cameraSpan);
        // A native read started before an event must not overwrite that event.
        if (cameraGeneration != _cameraGeneration) {
          final latest = _nextCamera;
          if (latest == null || _scheduledMap != map) {
            _again = true;
            return;
          }
          camera = latest;
          cameraGeneration = _cameraGeneration;
        }
      }
      if (_disposed || revision != _revision) return;
      final lon = camera.center.coordinates.lng.toDouble();
      final lat = camera.center.coordinates.lat.toDouble();
      final zoom = camera.zoom;
      final boundsSpan = MapPerformance.begin();
      final bounds = await map.coordinateBoundsForCamera(
        CameraOptions(
          center: camera.center,
          zoom: zoom,
          bearing: camera.bearing,
          pitch: camera.pitch,
          padding: camera.padding,
        ),
      );
      MapPerformance.finish('bounds_us', boundsSpan);
      if (_disposed || _paused || revision != _revision) return;
      if (cameraGeneration != _cameraGeneration || _scheduledMap != map) {
        _again = true;
        return;
      }
      _visibleBounds = bounds;
      _visibilityRanges.clear();
      // A byte-pressure cap belongs to the useful region that caused it. A
      // distant pan must allow normal detail again instead of pinning Z6.
      if (!_cache.values.any((s) => _cellVisible(s.cell))) {
        _resolutionCaps.clear();
      }
      _currentMap = map;
      _currentZoom = zoom;
      _renderRevision++;
      _longitude = lon;
      _latitude = lat;
      _useful = MarineCell.at(
        lon,
        lat,
        math.min(12, math.max(6, zoom.floor())),
      );
      _planRequests(bounds, lon, lat, zoom);
      _pruneCache();
      // Diagnostics and active flights follow this generation's working set.
      _failures.removeWhere((key, _) => !_wanted.containsKey(key));
      _failureReasons.removeWhere((key, _) => !_wanted.containsKey(key));
      hits += _wanted.keys.where((key) {
        final cached = _cache[key];
        return cached != null && cached.expires.isAfter(_now());
      }).length;
      for (final entry in _active.entries) {
        if (!_wanted.containsKey(entry.key)) _cancel(entry.key, entry.value);
      }
      if (zoom < MarineZoom.harbours) selection.reset();
      // Draw cached data immediately, even while the network is unavailable.
      await _renderCurrent();
      if (kDebugMode) {
        debugPrint(
          'NW220_VIEWPORT ${jsonEncode({
            ...metrics,
            'zoom': zoom,
            'lon': lon,
            'lat': lat,
            'bounds': [bounds.southwest.coordinates.toJson(), bounds.northeast.coordinates.toJson()],
          })}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NW220_VIEWPORT unavailable: ${e.runtimeType}');
      }
    } finally {
      _busy = false;
      if (_again && !_disposed && !_paused) {
        _again = false;
        unawaited(_synchronize(_scheduledMap ?? map));
      }
    }
    if (_disposed || _paused || revision != _revision) return;
    _drain ??= _drainWanted();
    try {
      await _drain;
    } catch (e) {
      if (kDebugMode) debugPrint('NW220_VIEWPORT drain: ${e.runtimeType}');
    }
  }

  void _planRequests(
    CoordinateBounds bounds,
    double lon,
    double lat,
    double zoom,
  ) {
    if (_requestCameraZoom != zoom.floor()) _resolutionCaps.clear();
    _requestCameraZoom = zoom.floor();
    final ideal = <String, int>{};
    final levels = <String, int>{};
    for (final family in sources.keys) {
      final threshold = family == 'harbours'
          ? MarineZoom.harbourPreload
          : family == 'seamarks' || family == 'underwater-hazards'
          ? MarineZoom.marksPreload
          : MarineZoom.depthsPreload;
      if (zoom < threshold) continue;
      final z = family == 'depth-contours'
          ? 12
          : family == 'harbours'
          ? zoom.floor().clamp(6, 14)
          : zoom.floor().clamp(12, family == 'soundings' ? 16 : 14);
      ideal[family] = math.min(z, _resolutionCaps[family] ?? z);
      levels[family] = ideal[family]!;
    }
    // Reserve sixteen slots for a transition, central refinement or margin.
    // When minimum legal resolutions still exceed the budget, ranges retain
    // the full demand but only the nearest 64 cells are admitted to work.
    while (true) {
      final counts = {
        for (final e in levels.entries)
          e.key: MarineCellRange(bounds, e.value).count,
      };
      if (counts.values.fold(0, (int a, b) => a + b) <= 48) break;
      final reducible =
          levels.keys
              .where(
                (f) =>
                    f != 'depth-contours' &&
                    levels[f]! > (f == 'harbours' ? 6 : 12),
              )
              .toList()
            ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      if (reducible.isEmpty) break;
      levels[reducible.first] = levels[reducible.first]! - 1;
    }
    _ranges.clear();
    for (final e in levels.entries) {
      _ranges[e.key] = MarineCellRange(bounds, e.value);
    }
    _plannedVisible = _ranges.values.fold(0, (a, r) => a + r.count);
    final next = <String, (String, MarineCell)>{};
    void take(Map<String, Iterator<MarineCell>> iterators) {
      while (iterators.isNotEmpty && next.length < maxSnapshots) {
        for (final family in iterators.keys.toList()) {
          final iterator = iterators[family]!;
          if (!iterator.moveNext()) {
            iterators.remove(family);
            continue;
          }
          final cell = iterator.current;
          next['$family/${cell.key}'] = (family, cell);
          if (next.length == maxSnapshots) break;
        }
      }
    }

    take({
      for (final e in _ranges.entries) e.key: e.value.cells(lon, lat).iterator,
    });
    // Keep detail at the centre even when the peripheral baseline is coarser.
    take({
      for (final e in ideal.entries)
        if (e.value != levels[e.key])
          e.key: MarineCellRange(bounds, e.value).cells(lon, lat).iterator,
    });
    take({
      for (final e in _ranges.entries)
        e.key: e.value.cells(lon, lat, marginOnly: true).iterator,
    });
    if (!listEquals(next.keys.toList(), _wanted.keys.toList())) {
      _budgetBlocked.clear();
      _dataRevision++;
    }
    _wanted
      ..clear()
      ..addAll(next);
  }

  List<String> _obsoleteKeys(Map<String, _Snapshot> cache) {
    final result = <String>[];
    for (final e in cache.entries) {
      final s = e.value;
      if (!_ranges.containsKey(s.family) ||
          (!_cellVisible(s.cell) && !_wanted.containsKey(e.key))) {
        result.add(e.key);
        continue;
      }
      if (_wanted.containsKey(e.key)) continue;
      final replacements = cache.entries
          .where(
            (other) =>
                other.key != e.key &&
                other.value.family == s.family &&
                other.value.complete &&
                _wanted.containsKey(other.key),
          )
          .map((other) => other.value.cell);
      if (s.cell.uncovered(replacements).isEmpty) result.add(e.key);
    }
    return result;
  }

  void _pruneCache() {
    final obsolete = _obsoleteKeys(_cache);
    for (final key in obsolete) {
      _bytes -= _cache.remove(key)!.bytes;
    }
    if (obsolete.isNotEmpty) {
      _budgetBlocked.clear();
      _dataRevision++;
    }
  }

  bool _admit(String key, _Snapshot snapshot) {
    final proposed = {..._cache, key: snapshot};
    final obsolete = _obsoleteKeys(proposed);
    for (final old in obsolete) {
      proposed.remove(old);
    }
    var size = proposed.values.fold(0, (int a, s) => a + s.bytes);
    final ranks = {for (final (i, k) in _wanted.keys.indexed) k: i};
    final optional =
        proposed.keys
            .where(
              (k) =>
                  k != key &&
                  !_cellVisible(proposed[k]!.cell) &&
                  (ranks[k] ?? maxSnapshots) > (ranks[key] ?? maxSnapshots),
            )
            .toList()
          ..sort(
            (a, b) =>
                (ranks[b] ?? maxSnapshots).compareTo(ranks[a] ?? maxSnapshots),
          );
    for (final victim in optional) {
      if (proposed.length <= maxSnapshots && size <= maxEncodedBytes) break;
      size -= proposed.remove(victim)!.bytes;
    }
    if (proposed.length > maxSnapshots || size > maxEncodedBytes) return false;
    // Commit the replacement and its evictions together. Never remove a useful
    // fallback before knowing that its replacement fits the encoded budgets.
    if (size < _bytes || proposed.length < _cache.length) {
      _budgetBlocked.clear();
    }
    for (final removed in _cache.keys.where((k) => !proposed.containsKey(k))) {
      if (_wanted.containsKey(removed)) _budgetBlocked.add(removed);
      _mosaics.remove(_cache[removed]!.family);
    }
    _cache
      ..clear()
      ..addAll(proposed);
    _bytes = size;
    _mosaics.remove(snapshot.family);
    return true;
  }

  Future<void> _renderCurrent() {
    final active = _rendering;
    if (active != null) {
      _renderAgain = true;
      return active;
    }
    final result = Completer<void>();
    _rendering = result.future;
    unawaited(
      _runRender().then(
        (_) {
          _rendering = null;
          result.complete();
        },
        onError: (Object error, StackTrace stack) {
          _rendering = null;
          if (kDebugMode) debugPrint('NW220_VIEWPORT render: $error');
          result.completeError(error, stack);
        },
      ),
    );
    return result.future;
  }

  Future<void> _runRender() async {
    do {
      _renderAgain = false;
      final map = _currentMap;
      if (map != null && !_disposed && !_paused) {
        await _render(map, _currentZoom, _renderRevision);
      }
    } while (_renderAgain && !_disposed && !_paused);
  }

  bool get _hasPending => _wanted.entries.any((entry) {
    if (_active.containsKey(entry.key) || _budgetBlocked.contains(entry.key)) {
      return false;
    }
    final cached = _cache[entry.key];
    if (cached != null && cached.expires.isAfter(_now())) return false;
    return !(_failures[entry.key]?.isAfter(_now()) ?? false);
  });

  Future<void> _drainWanted() async {
    Future<void> worker() async {
      while (!_disposed && !_paused) {
        MapEntry<String, (String, MarineCell)>? next;
        for (final entry in _wanted.entries) {
          if (_active.containsKey(entry.key) ||
              _budgetBlocked.contains(entry.key)) {
            continue;
          }
          final cached = _cache[entry.key];
          if (cached != null && cached.expires.isAfter(_now())) continue;
          if (_failures[entry.key]?.isAfter(_now()) ?? false) continue;
          next = entry;
          break;
        }
        if (next == null) return;
        await _fetch(next.key, next.value.$1, next.value.$2);
        if (!_disposed && !_paused) await _renderCurrent();
      }
    }

    try {
      await Future.wait([worker(), worker()]);
    } finally {
      _drain = null;
      if (!_disposed && !_paused && _hasPending) {
        _drain = _drainWanted();
        unawaited(
          _drain!.catchError((Object error) {
            if (kDebugMode) debugPrint('NW220_VIEWPORT drain: $error');
          }),
        );
      } else if (!_disposed &&
          !_paused &&
          _failures.keys.any(_wanted.containsKey)) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 16), () {
          _retryTimer = null;
          final map = _currentMap;
          if (map != null && !_disposed && !_paused) {
            unawaited(synchronize(map));
          }
        });
      }
    }
  }

  Future<void> _fetch(String key, String family, MarineCell cell) async {
    final client = _clientFactory();
    _active[key] = client;
    final watch = Stopwatch()..start();
    requests++;
    int? statusCode;
    try {
      final uri = ApiConfig.resolve(
        'api/v1/map/marine-features/$family/${cell.key}.geojson',
        baseUrl: apiBaseUrl,
      );
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 18));
      statusCode = response.statusCode;
      receivedBytes += response.bodyBytes.length;
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > 4 * 1024 * 1024) {
        throw StateError('snapshot budget');
      }
      final decodeSpan = MapPerformance.begin();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['type'] != 'FeatureCollection') {
        throw const FormatException('GeoJSON');
      }
      var features = (data['features'] as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
      MapPerformance.finish('decode_us', decodeSpan);
      if (_disposed ||
          _paused ||
          _cancelledFlights.contains(key) ||
          !_wanted.containsKey(key)) {
        return;
      }
      final previous = _cache[key];
      final marineStatus = response.headers['x-nowave-marine-status'];
      const completeStatuses = {
        'ok',
        'below-minzoom',
        'empty',
        'outside-coverage',
      };
      final complete =
          marineStatus == null || completeStatuses.contains(marineStatus);
      final retainPrevious =
          previous != null &&
          (!complete || (family == 'depth-contours' && features.isNotEmpty));
      if (retainPrevious) {
        final kept = {for (final f in previous.features) f['id'].toString(): f};
        for (final f in features) {
          kept.putIfAbsent(f['id'].toString(), () => f);
        }
        features = kept.values.toList();
      }
      final bytes = retainPrevious
          ? utf8
                .encode(
                  jsonEncode({
                    'type': 'FeatureCollection',
                    'features': features,
                  }),
                )
                .length
          : response.bodyBytes.length;
      final snapshot = _Snapshot(
        family,
        cell,
        features,
        bytes,
        _now().add(Duration(seconds: complete ? 300 : 15)),
        complete || (previous?.complete ?? false),
      );
      if (!_admit(key, snapshot)) {
        _budgetBlocked.add(key);
        // A memory refusal is not a network failure: lower detail or defer
        // until the view/cache changes instead of downloading every 15s.
        final minimum = family == 'harbours' ? 6 : 12;
        if (cell.z > minimum && _visibleBounds != null) {
          _resolutionCaps[family] = cell.z - 1;
          _planRequests(_visibleBounds!, _longitude, _latitude, _currentZoom);
          _pruneCache();
        }
        return;
      }
      _failureReasons.remove(key);
      _failures.remove(key);
      if (!complete) {
        _failures[key] = _now().add(const Duration(seconds: 15));
        _failureReasons[key] = 'degraded';
      }
      if (kDebugMode) {
        debugPrint(
          'NW220_FETCH ${jsonEncode({'key': key, 'features': features.length, 'bytes': bytes, 'ms': watch.elapsedMilliseconds, 'status': response.headers['x-nowave-marine-status']})}',
        );
      }
    } catch (e) {
      if (!_disposed &&
          !_paused &&
          !_cancelledFlights.contains(key) &&
          _wanted.containsKey(key)) {
        errors++;
        _failureReasons[key] = statusCode != null && statusCode != 200
            ? 'HTTP $statusCode'
            : e.runtimeType.toString();
        _failureReasons.removeWhere((key, _) => !_wanted.containsKey(key));
        _failures[key] = _now().add(const Duration(seconds: 15));
        if (kDebugMode) {
          debugPrint('NW220_FETCH_FAILED $key ${_failureReasons[key]}');
        }
      }
    } finally {
      _latencies.add(watch.elapsedMilliseconds);
      if (_latencies.length > 128) _latencies.removeAt(0);
      _active.remove(key);
      _cancelledFlights.remove(key);
      client.close();
      _failures.removeWhere((_, until) => until.isBefore(_now()));
    }
  }

  bool _pointVisible(double lon, double lat) {
    final bounds = _visibleBounds;
    if (bounds == null) return false;
    final sw = bounds.southwest.coordinates, ne = bounds.northeast.coordinates;
    if (lat < sw.lat || lat > ne.lat) return false;
    final rawSpan = (ne.lng - sw.lng).toDouble();
    if (bounds.infiniteBounds || rawSpan.abs() >= 360) return true;
    final span = rawSpan < 0 ? rawSpan + 360 : rawSpan;
    return (lon - sw.lng) % 360 <= span;
  }

  bool _cellVisible(MarineCell cell) {
    final bounds = _visibleBounds;
    if (bounds == null) return false;
    return _visibilityRanges
        .putIfAbsent(cell.z, () => MarineCellRange(bounds, cell.z))
        .contains(cell);
  }

  /// Read-only snapshot features. Callers must not mutate the maps/geometries.
  List<Map<String, dynamic>> features(String family) {
    final span = MapPerformance.begin();
    final all = <String, Map<String, dynamic>>{};
    final memo = _mosaics[family];
    final data = memo != null && memo.$1 == _dataRevision
        ? memo.$2
        : marineMosaic(
            [
              for (final s in _cache.values.where((s) => s.family == family))
                MarinePatch(s.cell, s.features, s.complete),
            ],
            {
              for (final e in _wanted.values.where((e) => e.$1 == family))
                e.$2.key,
            },
            hazardOutlines: family == 'underwater-hazards',
          );
    _mosaics[family] = (_dataRevision, data);
    for (final f in data) {
      all[f['id'].toString()] = f;
    }
    final useful = _useful;
    bool keepPoint(Map<String, dynamic> f) {
      if (useful == null || f['geometry']['type'] != 'Point') return false;
      final xy = f['geometry']['coordinates'] as List;
      if (_pointVisible((xy[0] as num).toDouble(), (xy[1] as num).toDouble())) {
        return true;
      }
      final c = MarineCell.at(
        (xy[0] as num).toDouble(),
        (xy[1] as num).toDouble(),
        useful.z,
      );
      final dx = (c.x - useful.x).abs();
      return math.min(dx, (1 << useful.z) - dx) <= 1 &&
          (c.y - useful.y).abs() <= 1;
    }

    for (final key in _retainedPoints.keys.toList()) {
      final point = _retainedPoints[key]!;
      final pointFamily = key.substring(0, key.indexOf('/'));
      final id = key.substring(key.indexOf('/') + 1);
      final xy = point['geometry']['coordinates'] as List;
      final replaced =
          pointFamily == family &&
          !all.containsKey(id) &&
          _cache.entries.any(
            (e) =>
                e.value.family == family &&
                e.value.complete &&
                _wanted.containsKey(e.key) &&
                e.value.cell.contains(
                  (xy[0] as num).toDouble(),
                  (xy[1] as num).toDouble(),
                ),
          );
      if (!_ranges.containsKey(pointFamily) || replaced || !keepPoint(point)) {
        _retainedBytes -= _retainedSizes.remove(key)!;
        _retainedPoints.remove(key);
      }
    }
    for (final entry in _retainedPoints.entries.where(
      (e) => e.key.startsWith('$family/'),
    )) {
      all.putIfAbsent(
        entry.key.substring(family.length + 1),
        () => entry.value,
      );
    }
    // Keep the first published point for retained identities, never substitute
    // a coordinate from a differently quantized upstream tile on zoom-in.
    for (final id in all.keys.toList()) {
      final key = '$family/$id';
      final retained = _retainedPoints[key];
      if (retained != null) {
        all[id] = retained;
      } else if (keepPoint(all[id]!) && _retainedPoints.length < 8000) {
        final size = utf8.encode(jsonEncode(all[id])).length;
        if (_retainedBytes + size <= 4 * 1024 * 1024) {
          _retainedPoints[key] = all[id]!;
          _retainedSizes[key] = size;
          _retainedBytes += size;
        }
      }
    }
    MapPerformance.finish('features_us', span);
    return all.values.toList();
  }

  Future<void> _render(MapboxMap map, double zoom, int revision) async {
    for (final entry in sources.entries) {
      var data = features(entry.key);
      // Keep Z10 preload separate from placement: fully transparent marks
      // must not reserve collision boxes for ports or other symbols.
      if ((entry.key == 'seamarks' || entry.key == 'underwater-hazards') &&
          zoom <= MarineZoom.marksPreload) {
        data = [];
      }
      if (entry.key == 'harbours') {
        final size = viewportSize();
        if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
          data = [];
        } else {
          final projectionSpan = MapPerformance.begin();
          final pixels = await map.pixelsForCoordinates([
            for (final f in data)
              Point(
                coordinates: Position.fromJson(
                  (f['geometry']['coordinates'] as List).cast<num>(),
                ),
              ),
          ]);
          MapPerformance.finish('projection_us', projectionSpan);
          if (_disposed || revision != _renderRevision) return;
          data = selection.select(data, pixels, zoom, size.width, size.height);
        }
      }
      if (_disposed || revision != _renderRevision) return;
      final previous = _encodedCollections[entry.value];
      final String encoded;
      if (previous != null && previous.matches(data)) {
        encoded = previous.json;
        MapPerformance.count('encode_reused');
      } else {
        final encodeSpan = MapPerformance.begin();
        encoded = jsonEncode({'type': 'FeatureCollection', 'features': data});
        _encodings++;
        MapPerformance.finish('encode_us', encodeSpan);
        _encodedCollections[entry.value] = _EncodedCollection(data, encoded);
      }
      if (_renderedData[entry.value] != encoded &&
          await map.style.styleSourceExists(entry.value) &&
          !_disposed &&
          revision == _renderRevision) {
        final publishSpan = MapPerformance.begin();
        await map.style.setStyleSourceProperty(entry.value, 'data', encoded);
        MapPerformance.finish('publish_us', publishSpan);
        if (_disposed || revision != _renderRevision) return;
        _renderedData[entry.value] = encoded;
      }
    }
  }
}
