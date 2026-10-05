import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Halo de précision autour de l'utilisateur, comme dans Plans : son rayon
/// est la marge d'erreur du GPS, en mètres. Avec une bonne précision il
/// reste caché sous le curseur ; il grandit quand la position devient
/// douteuse (démarrage, intérieur, position approximative).
///
/// Mapbox ne dessine son propre halo qu'avec le point bleu 2D. On ajoute
/// donc la même couche native nous-mêmes, pour le garder sous la flèche 3D :
/// Mapbox convertit toujours les mètres en pixels à chaque image.
class AccuracyHalo {
  /// [below] : couche à garder au-dessus du halo, si elle est déjà sur la
  /// carte.
  AccuracyHalo({this.below});

  static const layerId = 'nowave-accuracy-halo';

  /// Bleu iOS, léger à l'intérieur et plus marqué sur le bord.
  static const _fillColor = 0x26007AFF;
  static const _borderColor = 0x66007AFF;

  /// Glissement entre deux positions GPS, pour suivre le curseur que Mapbox
  /// anime aussi, au lieu de sauter.
  static const _transition = {'duration': 1000, 'delay': 0};

  /// Couche sous laquelle le halo se place à sa création.
  final String? below;

  /// Dernière position reçue pendant une mise à jour en cours.
  ({double latitude, double longitude, double accuracy})? _pending;

  /// Une mise à jour est en cours : les suivantes attendent leur tour.
  bool _updating = false;

  /// Couche du halo, sans image : Mapbox ne dessine que le disque.
  @visibleForTesting
  static LocationIndicatorLayer layer({
    required double latitude,
    required double longitude,
    required double accuracy,
  }) => LocationIndicatorLayer(
    id: layerId,
    // Sous les étiquettes du fond de carte et sous le curseur.
    slot: LayerSlot.MIDDLE,
    location: [latitude, longitude, 0],
    accuracyRadius: accuracy,
    accuracyRadiusColor: _fillColor,
    accuracyRadiusBorderColor: _borderColor,
  );

  /// Place le halo sur la position, de rayon [accuracy] en mètres. Crée la
  /// couche au premier appel et après chaque chargement de style, qui l'efface.
  Future<void> show(
    MapboxMap map, {
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    _pending = (latitude: latitude, longitude: longitude, accuracy: accuracy);
    if (_updating) return;
    _updating = true;
    try {
      // Seule la position la plus récente compte : les intermédiaires
      // arrivées pendant un appel sont sautées.
      for (var next = _pending; next != null; next = _pending) {
        _pending = null;
        await _apply(map, next);
      }
    } catch (_) {
      // Style en cours de rechargement : le halo revient au prochain
      // chargement de style ou à la prochaine position.
    } finally {
      _updating = false;
    }
  }

  /// Crée la couche si le style l'a effacée, sinon la déplace.
  Future<void> _apply(
    MapboxMap map,
    ({double latitude, double longitude, double accuracy}) position,
  ) async {
    final style = map.style;
    if (!await style.styleLayerExists(layerId)) {
      final halo = layer(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      final below = this.below;
      // Ajoutée après coup, la couche passerait par-dessus ; la placer
      // dessous garde la couche [below] lisible même dans un grand halo.
      if (below != null && await style.styleLayerExists(below)) {
        await style.addLayerAt(halo, LayerPosition(below: below));
      } else {
        await style.addLayer(halo);
      }
      // Les transitions n'existent pas dans la classe Dart de la couche.
      await Future.wait([
        style.setStyleLayerProperty(
          layerId,
          'location-transition',
          _transition,
        ),
        style.setStyleLayerProperty(
          layerId,
          'accuracy-radius-transition',
          _transition,
        ),
      ]);
      return;
    }
    await Future.wait([
      style.setStyleLayerProperty(layerId, 'location', [
        position.latitude,
        position.longitude,
        0,
      ]),
      style.setStyleLayerProperty(
        layerId,
        'accuracy-radius',
        position.accuracy,
      ),
    ]);
  }
}
