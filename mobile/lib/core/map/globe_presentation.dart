import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Only labels change at the continental threshold. Imagery, clouds and fog
/// fade inside the native renderer, without Dart work on every frame.
class GlobePresentation {
  bool? _applied;
  bool _running = false;
  double _zoom = 0;
  int _generation = 0;

  void styleLoaded() {
    _generation++;
    _applied = null;
  }

  Future<void> synchronize(MapboxMap map, double zoom) async {
    _zoom = zoom;
    if (_running) return;
    _running = true;
    try {
      while (_applied != (_zoom >= 4)) {
        final visible = _zoom >= 4;
        final generation = _generation;
        await map.style.setStyleImportConfigProperties('basemap', {
          'showPlaceLabels': visible,
          'showAdminBoundaries': visible,
        });
        if (generation == _generation) _applied = visible;
      }
    } catch (error) {
      // Decoration is optional; a later camera/idle event can retry.
      debugPrint('Présentation du globe non appliquée : $error');
    } finally {
      _running = false;
    }
  }
}
