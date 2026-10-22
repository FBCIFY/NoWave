import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'location_mast.dart';
import 'map_config.dart';

/// Repère GPS : un chevron couché, dont le cap vient du même flux que la
/// boussole de la carte, et un mât debout qui porte le pavillon du bateau.
/// La couche native du chevron applique la rotation et l'inclinaison de la
/// caméra ; le mât, une couche de symboles, reste face à l'écran.
class LocationMarker {
  static const layerId = 'nowave-location-marker';
  static const mastLayerId = 'nowave-location-mast';
  static const mastSourceId = 'nowave-location-mast';
  static const _small = 'nowave-location-arrow-small';
  static const _large = 'nowave-location-arrow-large';
  static const _dot = 'nowave-location-dot';
  static const _mast = 'nowave-location-mast';

  /// Glissement entre deux positions GPS, comme le repère natif que suit la
  /// caméra. Le chevron et le mât partagent la même position intermédiaire.
  static const glideDuration = Duration(seconds: 1);
  static const _glideTick = Duration(milliseconds: 33);
  static final _glideSteps =
      glideDuration.inMicroseconds ~/ _glideTick.inMicroseconds;

  MapboxMap? _map;
  double _pixelRatio = 1;
  double? _heading;
  String? _flagCountry;

  /// Position dessinée, qui glisse de [_from] vers [_to].
  ({double latitude, double longitude})? _shown, _from, _to;
  int _glideStep = 0;
  Timer? _glide;

  /// Position déjà envoyée à la source du mât.
  ({double latitude, double longitude})? _mastAt;

  Future<Map<String, MbxImage>>? _images;
  double? _imagesPixelRatio;
  Future<MbxImage>? _mastImage;
  bool _mastStale = false;
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
    bearingImageSize: 1,
    accuracyRadius: 0,
    emphasisCircleRadius: 0,
    imagePitchDisplacement: 0,
  );

  /// Mât debout au-dessus du chevron, dans le même emplacement : les
  /// pastilles des signalements, ajoutées sans emplacement, passent devant.
  @visibleForTesting
  static SymbolLayer mastLayer() => SymbolLayer(
    id: mastLayerId,
    sourceId: mastSourceId,
    slot: LayerSlot.TOP,
    iconImage: _mast,
    iconAnchor: IconAnchor.BOTTOM,
    // Le pied du mât, et non le bas de l'image, se pose sur la position.
    iconOffset: const [0, LocationMast.footMargin],
    iconPitchAlignment: IconPitchAlignment.VIEWPORT,
    iconRotationAlignment: IconRotationAlignment.VIEWPORT,
    iconSizeExpression: const [
      'step',
      ['zoom'],
      LocationMast.smallScale,
      MapConfig.detailedPuckMinZoom,
      1,
    ],
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
    iconEmissiveStrength: 1,
  );

  static String _point(({double latitude, double longitude}) at) => jsonEncode({
    'type': 'Feature',
    'properties': <String, Object>{},
    'geometry': {
      'type': 'Point',
      'coordinates': [at.longitude, at.latitude],
    },
  });

  /// Pavillon du bateau (code ISO à deux lettres), ou null pour le pavillon
  /// bleu uni. Redessiné à la prochaine mise à jour.
  set flagCountry(String? country) {
    if (country == _flagCountry) return;
    _flagCountry = country;
    _mastImage = null;
    _mastStale = true;
  }

  /// Sérialise les mutations et ne garde que la mesure la plus récente
  /// pendant un chargement d'images ou un appel au style. Une nouvelle
  /// position est rejointe en [glideDuration].
  Future<void> update(
    MapboxMap map, {
    required double pixelRatio,
    required double latitude,
    required double longitude,
    required double? heading,
  }) {
    _map = map;
    _pixelRatio = pixelRatio;
    _heading = heading;
    final target = (latitude: latitude, longitude: longitude);
    if (_shown == null) {
      _shown = _to = target;
    } else if (target != _to) {
      _from = _shown;
      _to = target;
      _glideStep = 0;
      _glide ??= Timer.periodic(_glideTick, (_) => _advance());
    }
    return _push();
  }

  void _advance() {
    final from = _from!, to = _to!;
    _glideStep++;
    final t = math.min(1.0, _glideStep / _glideSteps);
    _shown = (
      latitude: from.latitude + (to.latitude - from.latitude) * t,
      longitude: from.longitude + (to.longitude - from.longitude) * t,
    );
    if (t >= 1) {
      _glide?.cancel();
      _glide = null;
    }
    // Style en cours de rechargement : la prochaine étape retente.
    _push().ignore();
  }

  Future<void> _push() {
    final map = _map, shown = _shown;
    if (map == null || shown == null) return Future.value();
    _pending = layer(
      latitude: shown.latitude,
      longitude: shown.longitude,
      heading: _heading,
    );
    return _updating ??= _drain(
      map,
      _pixelRatio,
    ).whenComplete(() => _updating = null);
  }

  /// Arrête le glissement ; le repère reste où il est.
  void dispose() {
    _glide?.cancel();
    _glide = null;
    _map = null;
  }

  Future<void> _drain(MapboxMap map, double pixelRatio) async {
    final style = map.style;
    while (_pending != null) {
      final next = _pending!;
      _pending = null;
      final at = (latitude: next.location![0]!, longitude: next.location![1]!);
      if (!await style.styleLayerExists(layerId)) {
        await _addImages(style, pixelRatio);
        await style.addLayer(next);
        // La position glisse déjà, image par image : pas de seconde
        // interpolation, qui décalerait le chevron du mât.
        await style.setStyleLayerProperty(layerId, 'location-transition', {
          'duration': 0,
          'delay': 0,
        });
        // Le cap est déjà lissé par le flux de boussole. Éviter une seconde
        // interpolation, notamment lors du passage 359° → 0°.
        await style.setStyleLayerProperty(layerId, 'bearing-transition', {
          'duration': 0,
          'delay': 0,
        });
        if (!await style.styleSourceExists(mastSourceId)) {
          await style.addSource(
            GeoJsonSource(id: mastSourceId, data: _point(at)),
          );
        } else {
          await style.setStyleSourceProperty(mastSourceId, 'data', _point(at));
        }
        _mastAt = at;
        if (!await style.styleLayerExists(mastLayerId)) {
          await style.addLayer(mastLayer());
        }
        continue;
      }
      if (_mastStale) {
        _mastStale = false;
        await _addMastImage(style, pixelRatio);
      }
      await style.setStyleLayerProperties(
        layerId,
        jsonEncode({
          'location': next.location,
          'bearing': next.bearing,
          'bearing-image': next.bearingImageExpression ?? next.bearingImage,
        }),
      );
      if (at != _mastAt) {
        _mastAt = at;
        await style.setStyleSourceProperty(mastSourceId, 'data', _point(at));
      }
    }
  }

  Future<void> _addImages(StyleManager style, double pixelRatio) async {
    if (pixelRatio != _imagesPixelRatio) {
      _imagesPixelRatio = pixelRatio;
      _images = null;
      _mastImage = null;
    }
    final images = await (_images ??= _paintImages(pixelRatio));
    for (final entry in images.entries) {
      await _addImage(style, entry.key, pixelRatio, entry.value);
    }
    _mastStale = false;
    await _addMastImage(style, pixelRatio);
  }

  Future<void> _addMastImage(StyleManager style, double pixelRatio) async {
    final MbxImage image;
    try {
      image = await (_mastImage ??= _paintMast(pixelRatio));
    } catch (_) {
      // Un dessin raté sera refait à la prochaine installation.
      _mastImage = null;
      rethrow;
    }
    // addStyleImage remplace l'image : le nouveau pavillon s'affiche.
    await _addImage(style, _mast, pixelRatio, image);
  }

  // Images dessinées à la densité de l'écran : la même échelle au
  // sprite du style garde leur taille en points.
  static Future<void> _addImage(
    StyleManager style,
    String id,
    double pixelRatio,
    MbxImage image,
  ) => style.addStyleImage(id, pixelRatio, image, false, [], [], null);

  static Future<Map<String, MbxImage>> _paintImages(double pixelRatio) async =>
      {
        _small: await LocationMast.chevron(
          pixelRatio,
          scale: LocationMast.smallScale,
        ),
        _large: await LocationMast.chevron(pixelRatio),
        _dot: await LocationMast.dot(pixelRatio),
      };

  Future<MbxImage> _paintMast(double pixelRatio) async {
    final ui.Image? flag = await LocationMast.loadFlag(_flagCountry);
    try {
      return await LocationMast.mast(pixelRatio, flag);
    } finally {
      flag?.dispose();
    }
  }
}
