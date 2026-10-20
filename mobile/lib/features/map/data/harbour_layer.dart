import 'dart:ui' as ui;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'marine_tiles.dart';

/// Qualified port places, independent of detailed quay/pier geometries.
class HarbourLayer {
  static const harbourMinZoom = 6.0;
  static const sourceId = 'nowave-harbours';
  static const layerId = 'nowave-harbour-icons';

  static Future<void> addTo(MapboxMap map, {String? apiBaseUrl}) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed style installation remains retryable.
      }
      return addTo(map, apiBaseUrl: apiBaseUrl);
    }
    final install = _install(map, apiBaseUrl);
    _installing = install;
    try {
      await install;
    } finally {
      _installing = null;
    }
  }

  static Future<void>? _installing;

  static Future<void> _install(MapboxMap map, String? apiBaseUrl) async {
    final style = map.style;
    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        VectorSource(
          id: sourceId,
          tiles: [MarineTiles.template('harbours', apiBaseUrl: apiBaseUrl)],
          minzoom: harbourMinZoom,
          maxzoom: 14,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.25,
          attribution: MarineTiles.attribution(apiBaseUrl: apiBaseUrl),
        ),
      );
    }
    for (final marina in [false, true]) {
      final id = marina ? 'nowave-marina' : 'nowave-harbour';
      if (await style.hasStyleImage(id)) continue;
      await style.addStyleImage(
        id,
        3,
        await icon(marina: marina),
        false,
        [],
        [],
        null,
      );
    }
    if (!await style.styleLayerExists(layerId)) {
      await style.addLayer(layer());
    }
  }

  static SymbolLayer layer() => SymbolLayer(
    id: layerId,
    sourceId: sourceId,
    sourceLayer: 'harbour',
    slot: LayerSlot.TOP,
    minZoom: harbourMinZoom,
    filter: const [
      '==',
      ['geometry-type'],
      'Point',
    ],
    iconImageExpression: const [
      'match',
      ['get', 'category'],
      'marina',
      'nowave-marina',
      'nowave-harbour',
    ],
    iconSizeExpression: const [
      'interpolate',
      ['linear'],
      ['zoom'],
      6,
      0.62,
      8,
      0.72,
      10,
      0.85,
      12,
      1.0,
      14,
      1.08,
      18,
      1.12,
    ],
    iconAllowOverlap: false,
    iconIgnorePlacement: false,
    iconPadding: 3,
    iconAnchor: IconAnchor.CENTER,
    iconPitchAlignment: IconPitchAlignment.VIEWPORT,
    iconRotationAlignment: IconRotationAlignment.VIEWPORT,
    iconEmissiveStrength: 1,
    // Named places first, with generic ports ahead of marinas. Equal priority
    // is resolved in stable backend identity order, never by phone position.
    symbolSortKeyExpression: const [
      '+',
      [
        'case',
        [
          '==',
          ['get', 'name'],
          '',
        ],
        2,
        0,
      ],
      [
        'case',
        [
          '==',
          ['get', 'category'],
          'marina',
        ],
        1,
        0,
      ],
    ],
  );

  /// Original NoWave geometric artwork, CC0; drawn at 3×, no external sprite.
  /// A shared anchor silhouette; a small ring distinguishes qualified marinas.
  static Future<MbxImage> icon({required bool marina}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(3);
    final anchor = ui.Path()
      ..moveTo(12, 7)
      ..lineTo(12, 20)
      ..moveTo(8, 10)
      ..lineTo(16, 10)
      ..moveTo(4, 14)
      ..cubicTo(4, 18, 8, 20, 12, 20)
      ..cubicTo(16, 20, 20, 18, 20, 14)
      ..moveTo(4, 17)
      ..lineTo(4, 14)
      ..lineTo(7, 15)
      ..moveTo(17, 15)
      ..lineTo(20, 14)
      ..lineTo(20, 17)
      ..addOval(const ui.Rect.fromLTWH(9.6, 2.4, 4.8, 4.8));
    for (final halo in [true, false]) {
      final paint = ui.Paint()
        ..color = ui.Color(halo ? 0xFFF8FCFE : 0xFF395C70)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = halo ? 3.3 : 1.5
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      canvas.drawPath(anchor, paint);
      if (marina) {
        canvas.drawCircle(const ui.Offset(18.5, 5), 1.7, paint);
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return MbxImage(width: 72, height: 72, data: bytes!.buffer.asUint8List());
  }
}
