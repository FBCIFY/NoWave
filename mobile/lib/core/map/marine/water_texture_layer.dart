import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Ondulations statiques, découpées par les surfaces d'eau cartographiques.
/// Aucun lien avec les profondeurs ou les données marines métier.
class WaterTextureLayer {
  static const sourceId = 'nowave-water-mask';
  static const layerId = 'nowave-water-texture';
  static const imageId = 'nowave-water-ripples';
  static const _size = 512;

  Future<MbxImage>? _image;
  Future<void>? _installing;

  Future<void> addTo(MapboxMap map) async {
    final pending = _installing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Une nouvelle installation doit pouvoir retenter après un échec.
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

  Future<void> _install(MapboxMap map) async {
    final style = map.style;
    if (!await style.hasStyleImage(imageId)) {
      final image = await (_image ??= _makeImage());
      await style.addStyleImage(imageId, 1, image, false, [], [], null);
    }
    if (!await style.styleSourceExists(sourceId)) {
      // Les sources internes de Standard sont privées. Ce masque public
      // couvre aussi le globe, indépendamment de l'emprise de la bathymétrie.
      await style.addSource(
        VectorSource(
          id: sourceId,
          url: 'mapbox://mapbox.mapbox-streets-v8',
          minzoom: 0,
          maxzoom: 14,
          prefetchZoomDelta: 0,
          tileNetworkRequestsDelay: 0.25,
        ),
      );
    }
    if (!await style.styleLayerExists(layerId)) {
      await style.addLayer(
        FillLayer(
          id: layerId,
          sourceId: sourceId,
          sourceLayer: 'water',
          slot: LayerSlot.BOTTOM,
          fillPattern: imageId,
          // Le motif ne modifie pas la palette : seuls les traits bleus
          // transparents se superposent au raster / à la couleur de l'eau.
          fillOpacityExpression: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            0,
            0.06,
            6,
            0.09,
            11,
            0.10,
            14,
            0.05,
            16,
            0.015,
            17,
            0.004,
            18,
            0.0,
          ],
        ),
      );
    }
  }

  /// Un petit PNG (1 Mio une fois décodé), réutilisé au reload.
  /// Les traits irréguliers traversant un bord sont recopiés à l'autre bord
  /// pour une répétition sans couture. Pas de timer ni de rafraîchissement.
  Future<MbxImage> _makeImage() async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final random = math.Random(7319);
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round;
      for (var i = 0; i < 170; i++) {
        final x = random.nextDouble() * _size;
        final y = random.nextDouble() * _size;
        final length = 22 + random.nextDouble() * 56;
        final amplitude = 0.8 + random.nextDouble() * 1.8;
        final phase = random.nextDouble() * math.pi * 2;
        paint
          ..color = const ui.Color(0xFF377FA5)
              .withValues(alpha: 0.45 + random.nextDouble() * 0.45)
          ..strokeWidth = 0.6 + random.nextDouble() * 0.4;
        final path = ui.Path();
        for (var step = 0; step <= 24; step++) {
          final t = step / 24;
          final px = x + t * length;
          final py = y + amplitude * math.sin(t * math.pi * 2 + phase);
          if (step == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        for (final dx in [-_size, 0]) {
          for (final dy in [-_size, 0, _size]) {
            canvas.drawPath(
              path.shift(ui.Offset(dx.toDouble(), dy.toDouble())),
              paint,
            );
          }
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(_size, _size);
      picture.dispose();
      try {
        final bytes = (await image.toByteData(
          // Le pont Android attend une image encodée, comme les bouées.
          format: ui.ImageByteFormat.png,
        ))!;
        return MbxImage(
          width: _size,
          height: _size,
          data: bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
        );
      } finally {
        image.dispose();
      }
    } catch (_) {
      _image = null;
      rethrow;
    }
  }
}
