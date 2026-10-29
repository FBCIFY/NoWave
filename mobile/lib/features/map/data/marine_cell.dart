import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// XYZ ownership shared by the request planner and the display mosaic.
@immutable
class MarineCell {
  const MarineCell(this.z, this.x, this.y);
  final int z, x, y;
  String get key => '$z/$x/$y';

  static double tileY(double latitude, int z) {
    final phi = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    return ((1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) /
            2 *
            (1 << z))
        .clamp(0, (1 << z).toDouble());
  }

  static MarineCell at(double lon, double lat, int z) {
    final n = 1 << z;
    return MarineCell(
      z,
      ((lon + 180) / 360 * n).floor() % n,
      tileY(lat, z).floor().clamp(0, n - 1),
    );
  }

  bool contains(double lon, double lat) => at(lon, lat, z).key == key;
  bool covers(MarineCell other) =>
      z <= other.z &&
      x == other.x >> (other.z - z) &&
      y == other.y >> (other.z - z);
  bool overlaps(MarineCell other) => covers(other) || other.covers(this);
  double get west => x / (1 << z) * 360 - 180;
  double get east => (x + 1) / (1 << z) * 360 - 180;
  static double _latitude(double y) =>
      math.atan(
        (math.exp(math.pi * (1 - 2 * y)) - math.exp(-math.pi * (1 - 2 * y))) /
            2,
      ) *
      180 /
      math.pi;
  double get north => _latitude(y / (1 << z));
  double get south => _latitude((y + 1) / (1 << z));
  Iterable<MarineCell> get children sync* {
    for (var dy = 0; dy < 2; dy++) {
      for (var dx = 0; dx < 2; dx++) {
        yield MarineCell(z + 1, x * 2 + dx, y * 2 + dy);
      }
    }
  }

  /// Quadtree subtraction keeps disjoint cells, without a polygon union or a
  /// grid expanded to the finest zoom (which can be millions of cells).
  Iterable<MarineCell> uncovered(Iterable<MarineCell> coverage) sync* {
    final touching = coverage.where(overlaps).toList();
    if (touching.any((c) => c.covers(this))) return;
    if (touching.isEmpty) {
      yield this;
    } else {
      for (final child in children) {
        yield* child.uncovered(touching);
      }
    }
  }
}

/// One unwrapped XYZ rectangle. Antimeridian crossings remain contiguous;
/// normalization happens only when a request cell is emitted.
class MarineCellRange {
  MarineCellRange(CoordinateBounds bounds, this.z) {
    final n = 1 << z;
    final sw = bounds.southwest.coordinates, ne = bounds.northeast.coordinates;
    final rawSpan = ne.lng.toDouble() - sw.lng.toDouble();
    final span = bounds.infiniteBounds || rawSpan.abs() >= 360
        ? 360.0
        : (rawSpan < 0 ? rawSpan + 360 : rawSpan);
    left = ((sw.lng + 180) / 360 * n).floor();
    right = math.min(left + n - 1, ((sw.lng + span + 180) / 360 * n).floor());
    top = MarineCell.tileY(ne.lat.toDouble(), z).floor().clamp(0, n - 1);
    bottom = MarineCell.tileY(sw.lat.toDouble(), z).floor().clamp(0, n - 1);
  }
  final int z;
  late final int left, right, top, bottom;
  int get count => (right - left + 1) * (bottom - top + 1);

  bool contains(MarineCell cell, {int margin = 0}) {
    if (cell.z != z) return false;
    final n = 1 << z;
    final unwrapped = left + (cell.x - left) % n;
    final inX =
        unwrapped <= right + margin ||
        (margin > 0 && unwrapped - n >= left - margin);
    return inX &&
        cell.y >= math.max(0, top - margin) &&
        cell.y <= math.min(n - 1, bottom + margin);
  }

  /// Centre-out Chebyshev rings, bounded working memory even for a world view.
  Iterable<MarineCell> cells(
    double lon,
    double lat, {
    bool marginOnly = false,
  }) sync* {
    final n = 1 << z;
    final margin = marginOnly ? 1 : 0;
    final fullWidth = right - left + 1 == n;
    final l = fullWidth ? left : left - margin;
    final r = fullWidth ? right : math.min(right + margin, l + n - 1);
    final t = math.max(0, top - margin), b = math.min(n - 1, bottom + margin);
    var rawX = ((lon + 180) / 360 * n).floor();
    rawX += ((left + right - 2 * rawX) / (2 * n)).round() * n;
    final cx = rawX.clamp(l, r),
        cy = MarineCell.tileY(lat, z).floor().clamp(t, b);
    final radius = [cx - l, r - cx, cy - t, b - cy].reduce(math.max);
    bool include(int x, int y) =>
        x >= l &&
        x <= r &&
        y >= t &&
        y <= b &&
        (!marginOnly || x < left || x > right || y < top || y > bottom);
    for (var d = 0; d <= radius; d++) {
      if (d == 0) {
        if (include(cx, cy)) yield MarineCell(z, cx % n, cy);
        continue;
      }
      for (var x = math.max(l, cx - d); x <= math.min(r, cx + d); x++) {
        for (final y in [cy - d, cy + d]) {
          if (include(x, y)) yield MarineCell(z, x % n, y);
        }
      }
      for (var y = math.max(t, cy - d + 1); y <= math.min(b, cy + d - 1); y++) {
        for (final x in [cx - d, cx + d]) {
          if (include(x, y)) yield MarineCell(z, x % n, y);
        }
      }
    }
  }
}
