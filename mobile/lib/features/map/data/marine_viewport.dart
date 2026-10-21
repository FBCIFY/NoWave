import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import 'buoy_layer.dart';
import 'harbour_layer.dart';
import 'hydrography_layer.dart';
import '../../../core/map/marine/marine_zoom.dart';

/// Fixed XYZ ownership; contours always use Z12, including overzoom and reload.
@immutable
class MarineCell {
  const MarineCell(this.z, this.x, this.y);
  final int z, x, y;
  String get key => '$z/$x/$y';
  static MarineCell at(double lon, double lat, int z) {
    final n = 1 << z;
    final phi = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    return MarineCell(
      z,
      (((lon + 180) / 360 * n).floor() % n),
      ((1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2 * n)
          .floor()
          .clamp(0, n - 1),
    );
  }

  bool contains(double lon, double lat) => at(lon, lat, z).key == key;
}

/// Stable representative placement. Rejects from the initial collision group
/// become eligible at Z10. Retained ports precede all newcomers. Rotation can
/// force two retained ports together: the oldest stays drawn, both stay listed.
class HarbourSelection {
  final order = <String, int>{};
  final rejected = <String>{};
  int _sequence = 0;

  void reset() {
    order.clear();
    rejected.clear();
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
    final visibleIds = features.map((f) => f['id'].toString()).toSet();
    order.removeWhere((id, _) => !visibleIds.contains(id));
    rejected.removeWhere((id) => !visibleIds.contains(id));
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
    final occupied = <ScreenCoordinate>[];
    final selected = <Map<String, dynamic>>[];
    // 24 logical px PNG at max icon size 1.12 plus six px padding.
    final spacing = 24 * 1.12 + 6;
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
      if (zoom < MarineZoom.harbourEnrichment && rejected.contains(id)) {
        continue;
      }
      if (occupied.any(
        (q) => (q.x - p.x).abs() < spacing && (q.y - p.y).abs() < spacing,
      )) {
        if (!order.containsKey(id) && zoom < MarineZoom.harbourEnrichment) {
          rejected.add(id);
        }
        continue;
      }
      order.putIfAbsent(id, () => _sequence++);
      occupied.add(p);
      selected.add({
        ...f,
        'properties': {...f['properties'] as Map, 'selection_order': order[id]},
      });
    }
    return selected;
  }
}

class _Snapshot {
  _Snapshot(this.family, this.cell, this.features, this.bytes, this.expires);
  final String family;
  final MarineCell cell;
  final List<Map<String, dynamic>> features;
  final int bytes;
  final DateTime expires;
}

/// Public data only: two in-flight requests, at most nine cells per family,
/// 64 cached snapshots / 12 MiB encoded data. No Firebase headers or credentials.
/// Old contour geometry remains pinned while its fixed Z12 cell is useful.
class MarineViewport {
  MarineViewport({
    String? apiBaseUrl,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  }) : apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl,
       _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  final String apiBaseUrl;
  final DateTime Function() _now;
  final http.Client Function() _clientFactory;
  final _cache = <String, _Snapshot>{};
  final _renderedData = <String, String>{};
  final selection = HarbourSelection();
  final _active = <String, http.Client>{};
  final _cancelledFlights = <String>{};
  final _failures = <String, DateTime>{};
  final _wanted = <String, (String, MarineCell)>{};
  MarineCell? _useful;
  CoordinateBounds? _visibleBounds;
  int _retainedBytes = 0;
  final _retainedSizes = <String, int>{};
  final _retainedPoints = <String, Map<String, dynamic>>{};
  Timer? _timer;
  int _revision = 0;
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

  void styleLoaded() => _renderedData.clear();

  void schedule(MapboxMap map, {bool cameraChanged = false}) {
    if (_disposed || _paused) return;
    if (cameraChanged) {
      _revision++;
      for (final entry in _active.entries) {
        _cancel(entry.key, entry.value);
      }
    }
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(synchronize(map)),
    );
  }

  void resume(MapboxMap? map) {
    _paused = false;
    if (map != null) schedule(map);
  }

  void pause() {
    _paused = true;
    _again = false;
    _revision++;
    _timer?.cancel();
    _wanted.clear();
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
  }

  Future<void> synchronize(MapboxMap map) async {
    if (_disposed || _paused) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final revision = _revision;
    try {
      final camera = await map.getCameraState();
      if (_disposed || revision != _revision) return;
      final lon = camera.center.coordinates.lng.toDouble();
      final lat = camera.center.coordinates.lat.toDouble();
      final zoom = camera.zoom;
      final bounds = await map.coordinateBoundsForCamera(
        CameraOptions(
          center: camera.center,
          zoom: zoom,
          bearing: camera.bearing,
          pitch: camera.pitch,
        ),
      );
      _visibleBounds = bounds;
      _wanted.clear();
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
        final center = MarineCell.at(lon, lat, z);
        // Centre first, then nearest visible cells and immediate neighbours.
        // The nine-cell cap also applies to a pitched/wide viewport at Z6.
        final cells = <MarineCell>[];
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            final y = center.y + dy;
            if (y < 0 || y >= 1 << z) continue;
            cells.add(MarineCell(z, (center.x + dx) % (1 << z), y));
          }
        }
        cells.sort(
          (a, b) => ((a.x - center.x).abs() + (a.y - center.y).abs()).compareTo(
            (b.x - center.x).abs() + (b.y - center.y).abs(),
          ),
        );
        for (final cell in cells) {
          _wanted['$family/${cell.key}'] = (family, cell);
        }
      }
      // Diagnostics and retry metadata belong to the current request set too.
      // Successful degraded responses otherwise accumulate stale keys on pan.
      _failures.removeWhere((key, _) => !_wanted.containsKey(key));
      _failureReasons.removeWhere((key, _) => !_wanted.containsKey(key));
      for (final entry in _active.entries) {
        if (!_wanted.containsKey(entry.key)) {
          _cancel(entry.key, entry.value);
        }
      }
      // Remove old snapshots only outside the useful geographic region. Fixed
      // contour cells stay identical across zooms, style reload and reconnect.
      final useful = MarineCell.at(
        lon,
        lat,
        math.min(12, math.max(6, zoom.floor())),
      );
      _useful = useful;
      bool nearby(_Snapshot snapshot) {
        final c = snapshot.cell;
        if (snapshot.family == 'depth-contours' && _cellVisible(c)) return true;
        if (c.z < useful.z) {
          return _wanted.containsKey('${snapshot.family}/${c.key}');
        }
        final delta = c.z - useful.z;
        final x = c.x >> delta, y = c.y >> delta;
        final n = 1 << useful.z;
        final dx = (x - useful.x).abs();
        return math.min(dx, n - dx) <= 1 && (y - useful.y).abs() <= 1;
      }

      for (final key in _cache.keys.toList()) {
        if (!nearby(_cache[key]!) ||
            (_cache[key]!.family != 'depth-contours' &&
                !_wanted.containsKey(key))) {
          _bytes -= _cache.remove(key)!.bytes;
        }
      }
      if (zoom < MarineZoom.harbours) selection.reset();
      // Draw cached data immediately, even while the network is unavailable.
      await _render(map, zoom, revision);
      final queue = _wanted.entries.toList();
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < queue.length && !_disposed && revision == _revision) {
          final entry = queue[cursor++];
          final cached = _cache[entry.key];
          if (cached != null && cached.expires.isAfter(_now())) {
            hits++;
            continue;
          }
          if (_failures[entry.key]?.isAfter(_now()) ?? false) continue;
          await _fetch(entry.key, entry.value.$1, entry.value.$2, revision);
        }
      }

      await Future.wait([worker(), worker()]);
      if (!_disposed && revision == _revision) {
        await _render(map, zoom, revision);
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
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NW220_VIEWPORT unavailable: ${e.runtimeType}');
      }
    } finally {
      _busy = false;
      if (_again && !_disposed && !_paused) {
        _again = false;
        schedule(map);
      } else if (!_disposed &&
          !_paused &&
          _failures.keys.any(_wanted.containsKey)) {
        _timer?.cancel();
        _timer = Timer(
          const Duration(seconds: 16),
          () => unawaited(synchronize(map)),
        );
      }
    }
  }

  Future<void> _fetch(
    String key,
    String family,
    MarineCell cell,
    int revision,
  ) async {
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['type'] != 'FeatureCollection') {
        throw const FormatException('GeoJSON');
      }
      var features = (data['features'] as List)
          .map((f) => Map<String, dynamic>.from(f as Map))
          .toList();
      if (_disposed || revision != _revision || !_wanted.containsKey(key)) {
        return;
      }
      final previous = _cache[key];
      if (family == 'depth-contours' && previous != null) {
        final kept = {for (final f in previous.features) f['id'].toString(): f};
        for (final f in features) {
          kept.putIfAbsent(f['id'].toString(), () => f);
        }
        features = kept.values.toList();
      }
      final bytes = family == 'depth-contours' && previous != null
          ? utf8
                .encode(
                  jsonEncode({
                    'type': 'FeatureCollection',
                    'features': features,
                  }),
                )
                .length
          : response.bodyBytes.length;
      // Never evict useful retained geometry for a newcomer when saturated.
      if (_bytes - (previous?.bytes ?? 0) + bytes > 12 * 1024 * 1024 ||
          (_cache.length >= 64 && previous == null)) {
        throw StateError('viewport budget');
      }
      _bytes += bytes - (previous?.bytes ?? 0);
      _failureReasons.remove(key);
      _failures.remove(key);
      if (response.headers['x-nowave-marine-status'] == 'degraded') {
        _failures[key] = _now().add(const Duration(seconds: 15));
        _failureReasons[key] = 'degraded';
      }
      _cache[key] = _Snapshot(
        family,
        cell,
        features,
        bytes,
        _now().add(
          Duration(
            seconds: response.headers['x-nowave-marine-status'] == 'degraded'
                ? 15
                : 300,
          ),
        ),
      );
      if (kDebugMode) {
        debugPrint(
          'NW220_FETCH ${jsonEncode({'key': key, 'features': features.length, 'bytes': bytes, 'ms': watch.elapsedMilliseconds, 'status': response.headers['x-nowave-marine-status']})}',
        );
      }
    } catch (e) {
      if (!_disposed && revision == _revision) {
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
    return sw.lng <= ne.lng
        ? lon >= sw.lng && lon <= ne.lng
        : lon >= sw.lng || lon <= ne.lng;
  }

  bool _cellVisible(MarineCell cell) {
    final bounds = _visibleBounds;
    if (bounds == null) return false;
    final n = 1 << cell.z;
    final w = cell.x / n * 360 - 180, e = (cell.x + 1) / n * 360 - 180;
    double latitude(int y) =>
        math.atan(
          ((math.exp(math.pi * (1 - 2 * y / n)) -
                  math.exp(-math.pi * (1 - 2 * y / n))) /
              2),
        ) *
        180 /
        math.pi;
    final north = latitude(cell.y), south = latitude(cell.y + 1);
    final sw = bounds.southwest.coordinates, ne = bounds.northeast.coordinates;
    if (south > ne.lat || north < sw.lat) return false;
    return sw.lng <= ne.lng
        ? e >= sw.lng && w <= ne.lng
        : e >= sw.lng || w <= ne.lng;
  }

  List<Map<String, dynamic>> features(String family) {
    final all = <String, Map<String, dynamic>>{};
    for (final snapshot in _cache.values.where((s) => s.family == family)) {
      for (final f in snapshot.features) {
        all.putIfAbsent(f['id'].toString(), () => f);
      }
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
      if (!keepPoint(_retainedPoints[key]!)) {
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
        final size = await map.getSize();
        final pixels = await map.pixelsForCoordinates([
          for (final f in data)
            Point(
              coordinates: Position.fromJson(
                (f['geometry']['coordinates'] as List).cast<num>(),
              ),
            ),
        ]);
        if (_disposed || revision != _revision) return;
        data = selection.select(data, pixels, zoom, size.width, size.height);
      }
      if (_disposed || revision != _revision) return;
      final encoded = jsonEncode({
        'type': 'FeatureCollection',
        'features': data,
      });
      if (_renderedData[entry.value] != encoded &&
          await map.style.styleSourceExists(entry.value)) {
        await map.style.setStyleSourceProperty(entry.value, 'data', encoded);
        _renderedData[entry.value] = encoded;
      }
    }
  }
}
