/// Camera zooms are fractional; data preparation never enables placement.
abstract final class MarineZoom {
  static const raster = 5.0;
  static const harbourPreload = 6.0;
  static const harbours = 8.0;
  static const harbourEnrichment = 10.0;
  static const marksPreload = 10.0;
  static const marks = 12.0;
  static const depthsPreload = 12.0;
  static const depths = 13.0;

  /// Product decision: transparent at Z10, linear fade, fully opaque at Z12.
  static List<Object> marksOpacity({double nominal = 1}) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    marksPreload,
    0.0,
    marks,
    nominal,
  ];
}
