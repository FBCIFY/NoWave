import 'dart:convert';

import 'package:clipper2/clipper2.dart';

import 'marine_cell.dart';

/// Immutable downloaded geometry; display fragments never mutate its vertices.
class MarinePatch {
  const MarinePatch(this.cell, this.features, this.complete);
  final MarineCell cell;
  final List<Map<String, dynamic>> features;
  final bool complete;
}

/// Desired complete patches win locally. Old complete patches cover holes;
/// partial responses can add data only where no complete coverage is available.
List<Map<String, dynamic>> marineMosaic(
  List<MarinePatch> patches,
  Set<String> wanted, {
  bool hazardOutlines = false,
}) {
  patches.sort((a, b) {
    if (a.complete != b.complete) return a.complete ? -1 : 1;
    final desired = (wanted.contains(a.cell.key) ? 0 : 1).compareTo(
      wanted.contains(b.cell.key) ? 0 : 1,
    );
    return desired != 0 ? desired : b.cell.z.compareTo(a.cell.z);
  });
  final covered = <MarineCell>[];
  final all = <String, Map<String, dynamic>>{};
  for (final patch in patches) {
    final remaining = patch.cell.uncovered(covered).toList();
    if (remaining.isEmpty) continue;
    final whole =
        remaining.length == 1 && remaining.single.key == patch.cell.key;
    for (final feature in patch.features) {
      final geometry = feature['geometry'] as Map;
      final type = geometry['type'];
      if (type == 'Point') {
        final xy = geometry['coordinates'] as List;
        if (remaining.any(
          (c) =>
              c.contains((xy[0] as num).toDouble(), (xy[1] as num).toDouble()),
        )) {
          all.putIfAbsent(feature['id'].toString(), () => feature);
        }
        continue;
      }
      final polygon = type == 'Polygon' || type == 'MultiPolygon';
      final displayed = whole
          ? geometry
          : clipMarineGeometry(geometry, remaining);
      if (displayed == null) continue;
      final area = hazardOutlines && polygon;
      _add(all, feature, displayed, role: area ? 'area' : null);
      if (area) {
        // Clip the original boundary as lines. Drawing the boundary of the
        // clipped fill would invent dashed hazard edges along ownership cuts.
        final rings = type == 'Polygon'
            ? geometry['coordinates'] as List
            : (geometry['coordinates'] as List)
                  .expand((p) => p as List)
                  .toList();
        final boundary = <String, dynamic>{
          'type': 'MultiLineString',
          'coordinates': rings,
        };
        final outline = whole
            ? boundary
            : clipMarineGeometry(boundary, remaining);
        if (outline != null) _add(all, feature, outline, role: 'outline');
      }
    }
    // Partial responses cannot prove an area is empty, even when the fallback
    // is itself partial. Only complete coverage may hide older geometry.
    if (patch.complete) covered.addAll(remaining);
  }
  return all.values.toList();
}

void _add(
  Map<String, Map<String, dynamic>> all,
  Map<String, dynamic> feature,
  Map geometry, {
  String? role,
}) {
  final id = '${feature['id']}${role == 'outline' ? ':outline' : ''}';
  final previous = all[id];
  if (previous != null) {
    final old = previous['geometry'] as Map;
    if (identical(old, geometry) || jsonEncode(old) == jsonEncode(geometry)) {
      return;
    }
    final polygon = geometry['type'].toString().contains('Polygon');
    final parts = <dynamic>[];
    for (final g in [old, geometry]) {
      if (g['type'].toString().startsWith('Multi')) {
        parts.addAll(g['coordinates'] as List);
      } else {
        parts.add(g['coordinates']);
      }
    }
    all[id] = {
      ...previous,
      'geometry': {
        'type': polygon ? 'MultiPolygon' : 'MultiLineString',
        'coordinates': parts,
      },
    };
  } else if (role == null && identical(geometry, feature['geometry'])) {
    all[id] = feature;
  } else {
    final properties = {
      ...feature['properties'] as Map,
      'nw_source_id': feature['id'],
    };
    if (role != null) properties['nw_render_role'] = role;
    all[id] = {
      ...feature,
      'id': id,
      'geometry': geometry,
      'properties': properties,
    };
  }
}

/// Intersection with disjoint ownership rectangles. Source points and intact
/// geometries bypass this routine. Integer polygon clipping uses 1e-9 degrees;
/// only newly computed display fragments are quantized, never source snapshots.
Map<String, dynamic>? clipMarineGeometry(Map geometry, List<MarineCell> cells) {
  final type = geometry['type'];
  final coordinates = geometry['coordinates'] as List;
  if (type == 'LineString' || type == 'MultiLineString') {
    final lines = type == 'LineString' ? [coordinates] : coordinates;
    final parts = <List<List<num>>>[];
    for (final raw in lines) {
      final line = raw as List;
      for (final cell in cells) {
        List<List<num>>? part;
        for (var i = 1; i < line.length; i++) {
          final segment = _segment(line[i - 1] as List, line[i] as List, cell);
          if (segment == null) {
            part = null;
            continue;
          }
          if (part != null && _same(part.last, segment.first)) {
            part.add(segment.last);
          } else {
            part = segment;
            parts.add(part);
          }
        }
      }
    }
    if (parts.isEmpty) return null;
    return {
      'type': parts.length == 1 ? 'LineString' : 'MultiLineString',
      'coordinates': parts.length == 1 ? parts.single : parts,
    };
  }
  if (type != 'Polygon' && type != 'MultiPolygon') return null;
  const scale = 1e9;
  Path64 path(List points) => [
    for (final p in points)
      Point64.fromDouble(
        (p[0] as num).toDouble(),
        (p[1] as num).toDouble(),
        scale: scale,
      ),
  ];
  final engine = Clipper64();
  final polygons = type == 'Polygon' ? [coordinates] : coordinates;
  for (final polygon in polygons) {
    for (final (i, ring) in (polygon as List).indexed) {
      var p = path(ring as List);
      if (p.isPositive != (i == 0)) p = p.reversed.toList();
      engine.addSubject(p);
    }
  }
  for (final cell in cells) {
    engine.addClip(
      path([
        [cell.west, cell.south],
        [cell.east, cell.south],
        [cell.east, cell.north],
        [cell.west, cell.north],
      ]),
    );
  }
  final solution = engine.executeTree(ClipType.intersection, FillRule.nonZero);
  if (solution == null) throw StateError('Marine polygon clipping failed');
  List<List<double>> ring(Path64 p) => [
    for (final v in [...p, p.first]) [v.x / scale, v.y / scale],
  ];
  final result = <List<List<List<double>>>>[];
  void visit(PolyPath64 node) {
    if (node.polygon != null && !node.isHole) {
      result.add([
        ring(node.polygon!),
        for (final hole in node.children.where((c) => c.isHole))
          ring(hole.polygon!),
      ]);
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(solution.tree);
  if (result.isEmpty) return null;
  return {
    'type': result.length == 1 ? 'Polygon' : 'MultiPolygon',
    'coordinates': result.length == 1 ? result.single : result,
  };
}

bool _same(List a, List b) => a[0] == b[0] && a[1] == b[1];

List<List<num>>? _segment(List a, List b, MarineCell c) {
  final x = (a[0] as num).toDouble(), y = (a[1] as num).toDouble();
  final dx = (b[0] as num).toDouble() - x, dy = (b[1] as num).toDouble() - y;
  var lo = 0.0, hi = 1.0;
  final p = [-dx, dx, -dy, dy],
      q = [x - c.west, c.east - x, y - c.south, c.north - y];
  for (var i = 0; i < 4; i++) {
    if (p[i] == 0) {
      if (q[i] < 0) return null;
      continue;
    }
    final t = q[i] / p[i];
    if (p[i] < 0) {
      if (t > hi) return null;
      if (t > lo) lo = t;
    } else {
      if (t < lo) return null;
      if (t < hi) hi = t;
    }
  }
  if (hi <= lo || (dx == 0 && dy == 0)) return null;
  return [
    lo == 0 ? a.cast<num>() : [x + dx * lo, y + dy * lo],
    hi == 1 ? b.cast<num>() : [x + dx * hi, y + dy * hi],
  ];
}
