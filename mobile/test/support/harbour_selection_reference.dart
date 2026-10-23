// Unmodified quadratic selection from baseline 40feb7ff, retained as an oracle.
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:blueway/core/map/marine/marine_zoom.dart';

class ReferenceHarbourSelection {
  final order = <String, int>{};
  int _sequence = 0;

  void reset() {
    order.clear();
    _sequence = 0;
  }

  List<Map<String, dynamic>> select(
    List<Map<String, dynamic>> features,
    List<ScreenCoordinate?> pixels,
    double zoom,
    double width,
    double height,
  ) {
    if (zoom < MarineZoom.harbours) {
      reset();
      return [];
    }
    // A formerly selected port cannot keep priority after leaving the screen.
    const spacing = 24 * 1.12 + 6;
    final visibleIds = <String>{};
    for (var i = 0; i < features.length; i++) {
      final p = pixels[i];
      if (p != null &&
          p.x.isFinite &&
          p.y.isFinite &&
          p.x >= -spacing &&
          p.y >= -spacing &&
          p.x <= width + spacing &&
          p.y <= height + spacing) {
        visibleIds.add(features[i]['id'].toString());
      }
    }
    order.removeWhere((id, _) => !visibleIds.contains(id));
    final indexes = List.generate(features.length, (i) => i);
    int rank(Map<String, dynamic> f) {
      final p = f['properties'] as Map;
      return (p['name'] == '' ? 2 : 0) + (p['category'] == 'marina' ? 1 : 0);
    }

    indexes.sort((a, b) {
      final fa = features[a], fb = features[b];
      final ia = fa['id'].toString(), ib = fb['id'].toString();
      final oa = order[ia], ob = order[ib];
      if (oa != null || ob != null) {
        return (oa ?? 1 << 30).compareTo(ob ?? 1 << 30);
      }
      final r = rank(fa).compareTo(rank(fb));
      return r != 0 ? r : ia.compareTo(ib);
    });
    final occupied = <ScreenCoordinate>[];
    final selected = <Map<String, dynamic>>[];
    // 24 logical px PNG at max icon size 1.12 plus six px padding.
    for (final i in indexes) {
      final p = pixels[i];
      final f = features[i];
      final id = f['id'].toString();
      if (p == null ||
          !p.x.isFinite ||
          !p.y.isFinite ||
          p.x < -spacing ||
          p.y < -spacing ||
          p.x > width + spacing ||
          p.y > height + spacing) {
        continue;
      }
      if (occupied.any(
        (q) => (q.x - p.x).abs() < spacing && (q.y - p.y).abs() < spacing,
      )) {
        continue;
      }
      order.putIfAbsent(id, () => _sequence++);
      occupied.add(p);
      selected.add({
        ...f,
        'properties': {...f['properties'] as Map, 'selection_order': order[id]},
      });
    }
    return selected;
  }
}
