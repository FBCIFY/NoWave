import 'package:flutter/painting.dart';

/// Land-only HSL correction in encoded sRGB, preserving hue and lightness.
/// Interpolation towards the reduced colour also preserves those components:
/// with fixed H/L, RGB channels are affine functions of HSL saturation.
abstract final class LandColors {
  static const startZoom = 4.0;
  static const endZoom = 6.0;
  static const saturationFactor = 0.75;

  static HSLColor original(String hex) =>
      HSLColor.fromColor(Color(int.parse('FF${hex.substring(1)}', radix: 16)));

  static List<Object> reduced(String hex) {
    final hsl = original(hex);
    return [
      'hsl',
      hsl.hue,
      hsl.saturation * saturationFactor * 100,
      hsl.lightness * 100,
    ];
  }

  /// Evaluated by Mapbox on fractional zooms, without camera-time setters.
  static List<Object> color(String hex) => between(hex, reduced(hex));

  static List<Object> between(Object original, Object reduced) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    startZoom,
    original,
    endZoom,
    reduced,
  ];
}
