import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'marine_icon_image.dart';
import 'marine_tiles.dart';
import '../../../core/map/marine/marine_zoom.dart';

/// Qualified port places, independent of detailed quay/pier geometries.
class HarbourLayer {
  static const harbourMinZoom = MarineZoom.harbours;
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
        GeoJsonSource(
          id: sourceId,
          data: '{"type":"FeatureCollection","features":[]}',
          tolerance: 0,
          maxzoom: 18,
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
    iconAllowOverlap: true,
    iconIgnorePlacement: false,
    iconPadding: 3,
    iconAnchor: IconAnchor.CENTER,
    iconPitchAlignment: IconPitchAlignment.VIEWPORT,
    iconRotationAlignment: IconRotationAlignment.VIEWPORT,
    iconEmissiveStrength: 1,
    // Selection is performed once against projected screen positions by
    // MarineViewport; native placement must not evict a retained selection.
    symbolSortKeyExpression: const ['get', 'selection_order'],
  );

  /// PNG NoWave 72x72 ; même asset et même dimension que les autres symboles.
  static Future<MbxImage> icon({required bool marina}) async {
    final asset = marina
        ? 'assets/icons/harbours/marina.png'
        : 'assets/icons/harbours/port.png';
    return MarineIconImage.load(asset);
  }
}
