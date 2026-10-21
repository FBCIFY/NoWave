import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_config.dart';

/// Repère GPS dont le cap vient du même flux que la boussole de la carte.
/// La couche native applique la rotation et l'inclinaison de la caméra.
class LocationMarker {
  static const layerId = 'nowave-location-marker';
  static const _small = 'nowave-location-arrow-small';
  static const _large = 'nowave-location-arrow-large';
  static const _dot = 'nowave-location-dot';
  static const arrowScale = 1.125;

  Future<Map<String, MbxImage>>? _images;
  Future<void>? _updating;
  LocationIndicatorLayer? _pending;

  @visibleForTesting
  static LocationIndicatorLayer layer({
    required double latitude,
    required double longitude,
    required double? heading,
  }) => LocationIndicatorLayer(
    id: layerId,
    slot: LayerSlot.TOP,
    location: [latitude, longitude, 0],
    bearing: (heading ?? 0) % 360,
    bearingImage: heading == null ? _dot : _large,
    bearingImageExpression: heading == null
        ? null
        : const [
            'step',
            ['zoom'],
            _small,
            MapConfig.detailedPuckMinZoom,
            _large,
          ],
    bearingImageSize: heading == null ? 1 : arrowScale,
    accuracyRadius: 0,
    emphasisCircleRadius: 0,
    imagePitchDisplacement: 0,
  );

  /// Sérialise les mutations et ne garde que la mesure la plus récente
  /// pendant un chargement d'images ou un appel au style.
  Future<void> update(
    MapboxMap map, {
    required double pixelRatio,
    required double latitude,
    required double longitude,
    required double? heading,
  }) {
    _pending = layer(
      latitude: latitude,
      longitude: longitude,
      heading: heading,
    );
    return _updating ??= _drain(
      map,
      pixelRatio,
    ).whenComplete(() => _updating = null);
  }

  Future<void> _drain(MapboxMap map, double pixelRatio) async {
    final style = map.style;
    while (_pending != null) {
      final next = _pending!;
      _pending = null;
      if (!await style.styleLayerExists(layerId)) {
        final images = await (_images ??= _loadImages());
        for (final entry in images.entries) {
          await style.addStyleImage(
            entry.key,
            // Les PNG du puck natif sont en pixels physiques. Garder cette
            // taille lors de leur enregistrement dans le sprite du style.
            pixelRatio,
            entry.value,
            false,
            [],
            [],
            null,
          );
        }
        await style.addLayer(next);
        await style.setStyleLayerProperty(layerId, 'location-transition', {
          'duration': 1000,
          'delay': 0,
        });
        // Le cap est déjà lissé par le flux de boussole. Éviter une seconde
        // interpolation, notamment lors du passage 359° → 0°.
        await style.setStyleLayerProperty(layerId, 'bearing-transition', {
          'duration': 0,
          'delay': 0,
        });
      } else {
        await style.setStyleLayerProperties(
          layerId,
          jsonEncode({
            'location': next.location,
            'bearing': next.bearing,
            'bearing-image': next.bearingImageExpression ?? next.bearingImage,
            'bearing-image-size': next.bearingImageSize,
          }),
        );
      }
    }
  }

  static Future<Map<String, MbxImage>> _loadImages() async {
    final images = <String, MbxImage>{};
    for (final (id, asset) in [
      (_small, 'nowave_arrow_small.png'),
      (_large, 'nowave_arrow_large.png'),
      (_dot, 'nowave_dot_no_heading.png'),
    ]) {
      final data = await rootBundle.load('assets/images/$asset');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final decoded = img.decodePng(bytes)!;
      images[id] = MbxImage(
        width: decoded.width,
        height: decoded.height,
        data: bytes,
      );
    }
    return images;
  }
}
