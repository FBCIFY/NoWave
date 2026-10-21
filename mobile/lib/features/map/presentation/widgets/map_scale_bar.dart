import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Zoom et latitude du centre de la carte, les deux seules valeurs dont
/// dépend l'échelle.
typedef MapScaleCamera = ({double zoom, double latitude});

/// Règle de distance en bas à droite, comme sur les cartes marines : en
/// milles nautiques, et en pieds sous 0,1 NM. La règle native de Mapbox ne
/// connaît que les kilomètres et les miles terrestres.
class MapScaleBar extends StatelessWidget {
  const MapScaleBar({super.key, required this.camera});

  final ValueListenable<MapScaleCamera> camera;

  /// Sous ce zoom, la carte est un globe : une échelle n'y a pas de sens.
  static const minZoom = 5.0;

  /// Longueur maximale de la règle, en pixels.
  static const maxWidth = 80.0;

  static const _metersPerNauticalMile = 1852.0;
  static const _metersPerFoot = 0.3048;

  /// Circonférence de la Terre utilisée par la projection de Mapbox.
  static const _earthCircumference = 2 * math.pi * 6378137;

  /// Mapbox dessine le monde entier sur une tuile de 512 pixels au zoom 0.
  static const _tileSize = 512.0;

  /// Longueurs rondes proposées : en pieds sous 0,1 NM (608 ft), puis en
  /// milles nautiques.
  static const _feet = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0];
  static const _nauticalMiles = [
    0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, //
  ];
  static final _candidates = [
    for (final feet in _feet) (feet * _metersPerFoot, '${_format(feet)} ft'),
    for (final miles in _nauticalMiles)
      (miles * _metersPerNauticalMile, '${_format(miles)} NM'),
  ];

  /// Mètres couverts par un pixel au centre de la carte.
  static double metersPerPixel({
    required double zoom,
    required double latitude,
  }) {
    final cosine = math.cos(latitude.clamp(-85.0, 85.0) * math.pi / 180);
    return _earthCircumference * cosine / (_tileSize * math.pow(2, zoom));
  }

  /// Longueur à l'écran et texte de la règle ; null sur le globe.
  @visibleForTesting
  static ({double width, String label})? measure({
    required double zoom,
    required double latitude,
  }) {
    if (!zoom.isFinite || !latitude.isFinite || zoom < minZoom) return null;
    final perPixel = metersPerPixel(zoom: zoom, latitude: latitude);
    // La plus longue qui tient ; à très fort zoom, la plus courte.
    var (meters, label) = _candidates.first;
    for (final candidate in _candidates) {
      if (candidate.$1 / perPixel > maxWidth) break;
      (meters, label) = candidate;
    }
    return (width: meters / perPixel, label: label);
  }

  /// 0,5 plutôt que 0.5, et pas de décimale inutile.
  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString().replaceAll('.', ',');

  static const _color = Color(0xD9FFFFFF);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MapScaleCamera>(
    valueListenable: camera,
    builder: (context, camera, _) {
      final scale = measure(zoom: camera.zoom, latitude: camera.latitude);
      if (scale == null) return const SizedBox.shrink();
      return Semantics(
        label: 'Échelle ${scale.label}',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              scale.label,
              style: const TextStyle(
                color: _color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: _shadow,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: scale.width,
              height: 5,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: _color, width: 1.5),
                  right: BorderSide(color: _color, width: 1.5),
                  bottom: BorderSide(color: _color, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
