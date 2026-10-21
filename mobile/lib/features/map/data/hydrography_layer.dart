import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/api/api_config.dart';
import 'marine_tiles.dart';
import '../../../core/map/marine/marine_zoom.dart';

/// Contrat NoWave : courbes, échantillons ponctuels et dangers restent distincts.
class HydrographyLayer {
  HydrographyLayer({String? apiBaseUrl})
    : apiBaseUrl = apiBaseUrl ?? ApiConfig.marineBaseUrl;

  final String apiBaseUrl;
  static const contourSourceId = 'nowave-depth-contours';
  static const soundingSourceId = 'nowave-soundings';
  static const hazardSourceId = 'nowave-underwater-hazards';
  static const sourceIds = [contourSourceId, soundingSourceId, hazardSourceId];
  Future<void>? _installing;
  Future<void> addTo(MapboxMap map) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Un style remplacé ou une erreur restent retentables.
      }
      return addTo(map);
    }
    final install = _install(map);
    _installing = install;
    try {
      await install;
    } finally {
      _installing = null;
    }
  }

  static List<GeoJsonSource> sources({String? apiBaseUrl}) => [
    for (final id in sourceIds)
      GeoJsonSource(
        id: id,
        data: '{"type":"FeatureCollection","features":[]}',
        tolerance: 0,
        maxzoom: 18,
        attribution: MarineTiles.attribution(apiBaseUrl: apiBaseUrl),
      ),
  ];

  Future<void> _install(MapboxMap map) async {
    final style = map.style;
    for (final source in sources(apiBaseUrl: apiBaseUrl)) {
      if (!await style.styleSourceExists(source.id)) {
        await style.addSource(source);
      }
    }
    for (final kind in [
      'rock-unknown',
      'rock-submerged',
      'rock-exposed',
      'rock-awash',
      'rock-drying',
      'wreck',
      'obstruction',
      'unknown',
    ]) {
      final id = 'nowave-hazard-$kind';
      if (!await style.hasStyleImage(id)) {
        await style.addStyleImage(
          id,
          2,
          await _icon(kind),
          false,
          [],
          [],
          null,
        );
      }
    }
    // MIDDLE au-dessus du fond BOTTOM, avant les ouvrages MIDDLE.
    // Dangers TOP, puis aides fixes et bouées TOP installées au-dessus.
    for (final layer in layers()) {
      if (!await style.styleLayerExists(layer.id)) await style.addLayer(layer);
    }
  }

  // Lines are independent of label placement and have no upper zoom cutoff.
  static List<Object> get contourFilter => [
    '<=',
    ['get', 'display_minzoom'],
    ['zoom'],
  ];

  static List<Object> get depthTextSize => [
    'interpolate',
    ['linear'],
    ['zoom'],
    12,
    10.5,
    14,
    11.5,
    16,
    12.5,
    18,
    13.5,
  ];

  static List<Object> get contourSymbolSpacing => [
    'interpolate',
    ['linear'],
    ['zoom'],
    12,
    160,
    14,
    160,
    16,
    192,
    18,
    224,
  ];

  static List<Layer> layers() => [
    for (final major in [false, true])
      LineLayer(
        id: 'nowave-depth-${major ? 'major' : 'minor'}',
        sourceId: contourSourceId,
        slot: LayerSlot.MIDDLE,
        minZoom: MarineZoom.depths,
        filter: [
          'all',
          contourFilter,
          [
            '==',
            ['get', 'contour_class'],
            major ? 'major' : 'minor',
          ],
        ],
        lineColor: 0xFF507F99,
        lineWidth: major ? .95 : .55,
        lineOpacity: major ? .72 : .48,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    SymbolLayer(
      id: 'nowave-depth-labels',
      sourceId: contourSourceId,
      slot: LayerSlot.MIDDLE,
      minZoom: MarineZoom.depths,
      filter: [
        'all',
        ['has', 'depth_label'],
        contourFilter,
      ],
      symbolPlacement: SymbolPlacement.LINE,
      symbolSpacingExpression: contourSymbolSpacing,
      textFieldExpression: ['get', 'depth_label'],
      textSizeExpression: depthTextSize,
      textRotationAlignment: TextRotationAlignment.MAP,
      textPitchAlignment: TextPitchAlignment.MAP,
      textKeepUpright: true,
      textMaxAngle: 70,
      textColor: 0xFF354D5B,
      textHaloColor: 0xFFEDF8FC,
      textHaloWidth: .6,
      textPadding: 1,
      textAllowOverlap: false,
      textIgnorePlacement: false,
      symbolSortKeyExpression: ['get', 'value_m'],
    ),
    SymbolLayer(
      id: 'nowave-depth-soundings',
      sourceId: soundingSourceId,
      slot: LayerSlot.MIDDLE,
      minZoom: MarineZoom.depths,
      filter: [
        'match',
        ['get', 'nature'],
        ['modeled_grid_cell', 'point_sounding'],
        true,
        false,
      ],
      textFieldExpression: ['get', 'depth_label'],
      textSizeExpression: depthTextSize,
      textColor: 0xFF354D5B,
      textHaloColor: 0xFFEDF8FC,
      textHaloWidth: .5,
      textAllowOverlap: false,
      textIgnorePlacement: false,
      textPadding: 2,
      symbolSortKeyExpression: ['get', 'value_m'],
    ),
    FillLayer(
      id: 'nowave-hazard-areas',
      sourceId: hazardSourceId,
      slot: LayerSlot.TOP,
      minZoom: MarineZoom.marksPreload,
      filter: [
        '==',
        ['geometry-type'],
        'Polygon',
      ],
      fillColor: 0xFF596874,
      fillOpacityExpression: MarineZoom.marksOpacity(nominal: .07),
    ),
    LineLayer(
      id: 'nowave-hazard-outlines',
      sourceId: hazardSourceId,
      slot: LayerSlot.TOP,
      minZoom: MarineZoom.marksPreload,
      filter: [
        '!=',
        ['geometry-type'],
        'Point',
      ],
      lineColor: 0xFF596874,
      lineWidth: 1,
      lineOpacityExpression: MarineZoom.marksOpacity(nominal: .8),
      lineDasharray: [2, 2],
    ),
    SymbolLayer(
      id: 'nowave-hazard-points',
      sourceId: hazardSourceId,
      slot: LayerSlot.TOP,
      minZoom: MarineZoom.marksPreload,
      filter: [
        '==',
        ['geometry-type'],
        'Point',
      ],
      iconImageExpression: [
        'match',
        ['get', 'hazard_type'],
        'wreck',
        'nowave-hazard-wreck',
        'obstruction',
        'nowave-hazard-obstruction',
        'rock',
        [
          'match',
          ['get', 'water_level'],
          'awash',
          'nowave-hazard-rock-awash',
          'always_dry',
          'nowave-hazard-rock-exposed',
          'covers_and_uncovers',
          'nowave-hazard-rock-drying',
          'always_submerged',
          'nowave-hazard-rock-submerged',
          'nowave-hazard-rock-unknown',
        ],
        'nowave-hazard-unknown',
      ],
      iconSize: .75,
      iconOpacityExpression: MarineZoom.marksOpacity(),
      iconPadding: 3,
      iconAllowOverlap: false,
      iconIgnorePlacement: false,
      iconEmissiveStrength: 1,
      symbolSortKeyExpression: [
        '-',
        0,
        ['get', 'source_priority'],
      ],
    ),
  ];

  static Future<MbxImage> _icon(String kind) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = const Color(0xFF435764)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (kind.startsWith('rock')) {
      canvas.drawLine(const Offset(21, 21), const Offset(43, 43), paint);
      canvas.drawLine(const Offset(21, 43), const Offset(43, 21), paint);
      if (kind == 'rock-awash') {
        canvas.drawCircle(const Offset(32, 32), 17, paint);
      } else if (kind == 'rock-drying' || kind == 'rock-exposed') {
        canvas.drawPath(
          Path()
            ..moveTo(15, 46)
            ..lineTo(32, 15)
            ..lineTo(49, 46)
            ..close(),
          kind == 'rock-exposed'
              ? (Paint()
                  ..color = const Color(0xFF435764)
                  ..style = PaintingStyle.fill)
              : paint,
        );
      } else if (kind == 'rock-submerged') {
        for (final p in [
          const Offset(32, 13),
          const Offset(32, 51),
          const Offset(13, 32),
          const Offset(51, 32),
        ]) {
          canvas.drawCircle(p, 1.5, paint);
        }
      }
    } else if (kind == 'wreck') {
      canvas.drawPath(
        Path()
          ..moveTo(12, 32)
          ..lineTo(22, 40)
          ..lineTo(46, 40)
          ..lineTo(52, 32)
          ..close(),
        paint,
      );
      canvas.drawLine(const Offset(31, 18), const Offset(31, 44), paint);
      canvas.drawLine(const Offset(23, 24), const Offset(39, 24), paint);
    } else if (kind == 'obstruction') {
      // Unqualified artificial obstacle: a small, open interrupted enclosure.
      // No diamond, depth, water level or danger qualification is inferred.
      paint.strokeWidth = 2;
      final rect = Rect.fromCircle(center: const Offset(32, 32), radius: 13);
      for (var i = 0; i < 4; i++) {
        canvas.drawArc(rect, i * 1.5708 + .2, 1.1, false, paint);
      }
      canvas.drawLine(const Offset(27, 32), const Offset(37, 32), paint);
    } else {
      // Unknown family must never silently become a rock.
      paint.strokeWidth = 2;
      canvas.drawLine(const Offset(29, 32), const Offset(35, 32), paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return MbxImage(width: 64, height: 64, data: data!.buffer.asUint8List());
  }
}
