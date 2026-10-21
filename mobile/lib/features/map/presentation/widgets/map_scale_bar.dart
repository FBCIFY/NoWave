import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/haptics/app_haptics.dart';

/// Zoom et latitude du centre de la carte, les deux seules valeurs dont
/// dépend l'échelle.
typedef MapScaleCamera = ({double zoom, double latitude});

/// Règle de distance en bas à gauche, en milles nautiques par défaut. La
/// règle native de Mapbox ne connaît que les kilomètres et les miles
/// terrestres. Un appui bascule vers les mètres et kilomètres ; le choix est
/// gardé d'un lancement à l'autre.
class MapScaleBar extends StatefulWidget {
  const MapScaleBar({super.key, required this.camera, this.preferences});

  final ValueListenable<MapScaleCamera> camera;
  final Future<SharedPreferences> Function()? preferences;

  /// Sous ce zoom, la carte est un globe : une échelle n'y a pas de sens.
  static const minZoom = 5.0;

  /// Longueur maximale de la règle, en pixels.
  static const maxWidth = 80.0;

  static const _metersPerNauticalMile = 1852.0;

  /// Circonférence de la Terre utilisée par la projection de Mapbox.
  static const _earthCircumference = 2 * math.pi * 6378137;

  /// Mapbox dessine le monde entier sur une tuile de 512 pixels au zoom 0.
  static const _tileSize = 512.0;

  /// Longueurs rondes proposées, en mètres. En nautique, sous 0,1 NM, la
  /// règle passe en mètres.
  static const _shortMeters = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0];
  static const _nauticalMiles = [
    0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, //
  ];
  static const _metricMeters = [
    ..._shortMeters,
    200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0, //
    100000.0, 200000.0, 500000.0, 1000000.0,
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
    required bool nautical,
  }) {
    if (!zoom.isFinite || !latitude.isFinite || zoom < minZoom) return null;
    final perPixel = metersPerPixel(zoom: zoom, latitude: latitude);
    final candidates = nautical
        ? [
            for (final meters in _shortMeters) (meters, '${_format(meters)} m'),
            for (final miles in _nauticalMiles)
              (miles * _metersPerNauticalMile, '${_format(miles)} NM'),
          ]
        : [
            for (final meters in _metricMeters)
              (
                meters,
                meters < 1000
                    ? '${_format(meters)} m'
                    : '${_format(meters / 1000)} km',
              ),
          ];
    // La plus longue qui tient ; à très fort zoom, la plus courte.
    var (meters, label) = candidates.first;
    for (final candidate in candidates) {
      if (candidate.$1 / perPixel > maxWidth) break;
      (meters, label) = candidate;
    }
    return (width: meters / perPixel, label: label);
  }

  /// 0,5 plutôt que 0.5, et pas de décimale inutile.
  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString().replaceAll('.', ',');

  @override
  State<MapScaleBar> createState() => _MapScaleBarState();
}

class _MapScaleBarState extends State<MapScaleBar> {
  static const _nauticalKey = 'map_scale_nautical';
  static const _color = Color(0xD9FFFFFF);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];

  bool _nautical = true;

  Future<SharedPreferences> _preferences() =>
      (widget.preferences ?? SharedPreferences.getInstance)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = (await _preferences()).getBool(_nauticalKey);
      if (mounted && saved != null) setState(() => _nautical = saved);
    } catch (_) {
      // Préférence illisible : on garde les milles nautiques.
    }
  }

  Future<void> _toggle() async {
    AppHaptics.selection();
    final nautical = !_nautical;
    setState(() => _nautical = nautical);
    try {
      await (await _preferences()).setBool(_nauticalKey, nautical);
    } catch (_) {
      // Le choix vaut pour cette session même s'il n'a pas pu être gardé.
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MapScaleCamera>(
    valueListenable: widget.camera,
    builder: (context, camera, _) {
      final scale = MapScaleBar.measure(
        zoom: camera.zoom,
        latitude: camera.latitude,
        nautical: _nautical,
      );
      if (scale == null) return const SizedBox.shrink();
      return Semantics(
        button: true,
        label:
            'Échelle ${scale.label}. Toucher pour passer en '
            '${_nautical ? 'kilomètres' : 'milles nautiques'}.',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_toggle()),
          child: Padding(
            // Zone de toucher plus large que la règle, qui est fine.
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
          ),
        ),
      );
    },
  );
}
