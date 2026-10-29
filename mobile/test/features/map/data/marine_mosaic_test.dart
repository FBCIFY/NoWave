import 'dart:convert';

import 'package:blueway/features/map/data/marine_cell.dart';
import 'package:blueway/features/map/data/marine_mosaic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Map<String, dynamic> shape(String id, String type, List coordinates) => {
  'type': 'Feature',
  'id': id,
  'geometry': {'type': type, 'coordinates': coordinates},
  'properties': {'source_id': id, 'depth_label': '1.25'},
};

List<List<double>> rectangle(MarineCell c) => [
  [c.west, c.south],
  [c.east, c.south],
  [c.east, c.north],
  [c.west, c.north],
  [c.west, c.south],
];

double geometryArea(Map g) {
  double ringArea(List ring) {
    var area = 0.0;
    for (var i = 1; i < ring.length; i++) {
      area +=
          (ring[i - 1][0] as num) * (ring[i][1] as num) -
          (ring[i][0] as num) * (ring[i - 1][1] as num);
    }
    return area.abs() / 2;
  }

  double polygonArea(List rings) =>
      ringArea(rings.first as List) -
      rings.skip(1).fold(0.0, (a, r) => a + ringArea(r as List));
  return g['type'] == 'Polygon'
      ? polygonArea(g['coordinates'] as List)
      : (g['coordinates'] as List).fold(
          0.0,
          (a, p) => a + polygonArea(p as List),
        );
}

void main() {
  CoordinateBounds bounds(double w, double s, double e, double n) =>
      CoordinateBounds(
        southwest: Point(coordinates: Position(w, s)),
        northeast: Point(coordinates: Position(e, n)),
        infiniteBounds: false,
      );

  test(
    'visible ranges cross the antimeridian without duplicates or invalid XYZ',
    () {
      final range = MarineCellRange(bounds(170, -5, -170, 5), 3);
      final cells = range.cells(179, 0).toList();
      expect(cells, hasLength(4));
      expect(cells.map((c) => c.x).toSet(), {0, 7});
      final margin = range.cells(179, 0, marginOnly: true).toList();
      expect({
        ...cells.map((c) => c.key),
        ...margin.map((c) => c.key),
      }, hasLength(cells.length + margin.length));
      expect(cells.every((c) => range.contains(c)), isTrue);
      expect(margin.every((c) => range.contains(c, margin: 1)), isTrue);
    },
  );

  test('world and polar ranges are lazy, bounded and start at the camera', () {
    final world = MarineCellRange(bounds(-180, -90, 180, 90), 16);
    expect(world.count, 1 << 32);
    final first = world.cells(179.9, 89).take(64).toList();
    expect(first.first.key, MarineCell.at(179.9, 89, 16).key);
    expect(first.map((c) => c.key).toSet(), hasLength(64));
    expect(
      first.every((c) => c.x >= 0 && c.x < 65536 && c.y >= 0 && c.y < 65536),
      isTrue,
    );
    final small = MarineCellRange(bounds(-180, -90, 180, 90), 2);
    expect(small.cells(0, 0).length, 16);
    expect(small.cells(0, 0, marginOnly: true), isEmpty);
  });

  const parent = MarineCell(1, 1, 1);
  const child = MarineCell(2, 2, 2);
  final old = shape('old', 'Polygon', [rectangle(parent)]);
  final detail = shape('new', 'Polygon', [rectangle(child)]);

  test('one ready child immediately replaces only its area and preserves source geometry', () {
    final before = jsonEncode(old);
    final result = marineMosaic(
      [
        MarinePatch(parent, [old], true),
        MarinePatch(child, [detail], true),
      ],
      {child.key},
    );
    expect(result.map((f) => f['id']).toSet(), {'old', 'new'});
    final total = result.fold(
      0.0,
      (a, f) => a + geometryArea(f['geometry'] as Map),
    );
    expect(total, closeTo(geometryArea(old['geometry'] as Map), 1e-6));
    expect(
      geometryArea(
        result.firstWhere((f) => f['id'] == 'old')['geometry'] as Map,
      ),
      closeTo(
        geometryArea(old['geometry'] as Map) -
            geometryArea(detail['geometry'] as Map),
        1e-6,
      ),
    );
    expect(jsonEncode(old), before);
  });

  test('partial does not erase fallback; complete empty really replaces its region', () {
    final partial = marineMosaic(
      [
        MarinePatch(parent, [old], true),
        MarinePatch(child, [detail], false),
      ],
      {child.key},
    );
    expect(partial, [old]);
    final empty = marineMosaic(
      [
        MarinePatch(parent, [old], true),
        const MarinePatch(child, [], true),
      ],
      {child.key},
    );
    expect(empty.single['id'], 'old');
    expect(
      geometryArea(empty.single['geometry'] as Map),
      closeTo(
        geometryArea(old['geometry'] as Map) -
            geometryArea(detail['geometry'] as Map),
        1e-6,
      ),
    );
    final coarse = marineMosaic(
      [
        MarinePatch(child, [detail], true),
        const MarinePatch(parent, [], true),
      ],
      {parent.key},
    );
    expect(coarse, isEmpty);
  });

  for (final complete in [false, true]) {
    test(
      'empty Z13 responses ${complete ? 'replace' : 'preserve'} degraded Z12 hazards',
      () {
        final coarse = MarineCell.at(-4.5, 48.3, 12);
        final children = coarse.children.toList();
        final cell = children.first;
        final latitude = (cell.south + cell.north) / 2;
        final hazard = shape('cached-hazard', 'LineString', [
          [(3 * cell.west + cell.east) / 4, latitude],
          [(cell.west + 3 * cell.east) / 4, latitude],
        ]);
        final cached = MarinePatch(coarse, [hazard], false);
        final before = jsonEncode(hazard);
        expect(marineMosaic([cached], {coarse.key}), [hazard]);

        final result = marineMosaic(
          [
            cached,
            for (final child in children) MarinePatch(child, [], complete),
          ],
          children.map((c) => c.key).toSet(),
          hazardOutlines: true,
        );

        expect(result, complete ? isEmpty : equals([hazard]));
        expect(jsonEncode(hazard), before);
      },
    );
  }

  test(
    'polygon holes, concavity and disconnected multipolygons survive clipping',
    () {
      // No outer vertex is inside this child; enclosing rings must still clip.
      final hole = [
        [10, -20],
        [20, -20],
        [20, -10],
        [10, -10],
        [10, -20],
      ];
      final polygon = {
        'type': 'Polygon',
        'coordinates': [rectangle(parent), hole],
      };
      final clipped = clipMarineGeometry(polygon, [child])!;
      expect(clipped['type'], 'Polygon');
      expect(clipped['coordinates'], hasLength(2));
      expect(
        geometryArea(clipped),
        closeTo(geometryArea(detail['geometry'] as Map) - 100, 1e-6),
      );
      final concave = {
        'type': 'Polygon',
        'coordinates': [
          [
            [0, -50],
            [50, -50],
            [50, -40],
            [10, -40],
            [10, -10],
            [0, -10],
            [0, -50],
          ],
        ],
      };
      expect(
        geometryArea(clipMarineGeometry(concave, [child])!),
        closeTo(800, 1e-6),
      );
      final multi = {
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [1, -2],
              [2, -2],
              [2, -1],
              [1, -1],
              [1, -2],
            ],
          ],
          [
            [
              [3, -4],
              [4, -4],
              [4, -3],
              [3, -3],
              [3, -4],
            ],
          ],
        ],
      };
      final pieces = clipMarineGeometry(multi, [child])!;
      expect(pieces['type'], 'MultiPolygon');
      expect(geometryArea(pieces), closeTo(2, 1e-9));
    },
  );

  test(
    'line clipping discards tangencies and keeps original interior vertices',
    () {
      final line = {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [-5, -20],
            [10, -20],
            [100, -20],
          ],
          [
            [-1, 1],
            [0, 0],
          ],
        ],
      };
      final clipped = clipMarineGeometry(line, [child])!;
      expect(clipped['type'], 'LineString');
      expect(clipped['coordinates'], [
        [0.0, -20.0],
        [10, -20],
        [90.0, -20.0],
      ]);
    },
  );

  test(
    'hazard outlines follow original edges, never the new ownership cut',
    () {
      final result = marineMosaic(
        [
          MarinePatch(parent, [old], true),
          const MarinePatch(child, [], true),
        ],
        {child.key},
        hazardOutlines: true,
      );
      final area = result.singleWhere((f) => f['id'] == 'old');
      expect(area['properties']['nw_render_role'], 'area');
      final outline = result.singleWhere((f) => f['id'] == 'old:outline');
      final g = outline['geometry'] as Map;
      final lines = g['type'] == 'LineString'
          ? [g['coordinates']]
          : g['coordinates'] as List;
      for (final line in lines) {
        for (var i = 1; i < line.length; i++) {
          final a = line[i - 1], b = line[i];
          expect(
            (a[0] == parent.west && b[0] == parent.west) ||
                (a[0] == parent.east && b[0] == parent.east) ||
                (a[1] == parent.north && b[1] == parent.north) ||
                (a[1] == parent.south && b[1] == parent.south),
            isTrue,
          );
        }
      }
    },
  );

  test('shared hazard identity keeps fill and original outlines separate at mixed zooms', () {
    final updated = {...detail, 'id': 'old'};
    final result = marineMosaic(
      [
        MarinePatch(parent, [old], true),
        MarinePatch(child, [updated], true),
      ],
      {child.key},
      hazardOutlines: true,
    );
    expect(result, hasLength(2));
    expect(
      result.singleWhere(
        (f) => f['id'] == 'old',
      )['properties']['nw_render_role'],
      'area',
    );
    expect(
      result.singleWhere((f) => f['id'] == 'old:outline')['geometry']['type'],
      'MultiLineString',
    );
    expect(
      geometryArea(
        result.singleWhere((f) => f['id'] == 'old')['geometry'] as Map,
      ),
      closeTo(geometryArea(old['geometry'] as Map), 1e-6),
    );
  });

  test(
    'adjacent fragments with a shared source ID are combined, not discarded',
    () {
      final sibling = parent.children.last;
      final a = shape('same-source', 'LineString', [
        [5, -20],
        [20, -20],
      ]);
      final b = shape('same-source', 'LineString', [
        [100, -80],
        [120, -80],
      ]);
      final result = marineMosaic(
        [
          MarinePatch(child, [a], true),
          MarinePatch(sibling, [b], true),
        ],
        {child.key, sibling.key},
      );
      expect(result.single['id'], 'same-source');
      expect(result.single['geometry']['type'], 'MultiLineString');
      expect(result.single['geometry']['coordinates'], hasLength(2));
    },
  );
}
