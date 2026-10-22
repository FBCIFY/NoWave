import '../land_colors.dart';

/// Palette cartographique : terres naturelles et océan bleu profond.
/// Partagée entre le style initial et sa réinstallation après un reload.
class MarinePalette {
  static const water = '#002D51';
  static const forest = '#395B32';
  static const scrub = '#627545';
  static const vegetation = '#7C8950';
  static const crop = '#A39F6B';
  static const snow = '#ECEDE5';

  /// Mapbox Standard glyphs use the app font.
  static const labelFont = ['Raleway Medium'];

  static final basemapConfig = <String, Object>{
    'lightPreset': 'day',
    'theme': 'faded',
    'font': 'Raleway',
    for (final entry in land.entries) entry.key: LandColors.color(entry.value),
    'colorPlaceLabels': '#3A4843',
    'colorAdminBoundaries': '#CED1C8',
    'colorWater': water,
    'showRoadLabels': false,
    'showPointOfInterestLabels': false,
    'showTransitLabels': false,
    'showAdminBoundaries': false,
    'show3dObjects': false,
  };

  /// Only surface colours: water, labels, boundaries and symbols are excluded.
  static const land = <String, String>{
    'colorLand': '#C4AD80',
    'colorGreenspace': '#627545',
    'colorCommercial': '#B5B1A2',
    'colorEducation': '#B5B1A2',
    'colorMedical': '#B5B1A2',
    'colorIndustrial': '#AAA99D',
    'colorBuildings': '#BDB8A9',
    'colorMotorways': '#BEC7C7',
    'colorTrunks': '#C6CDCC',
    'colorRoads': '#D1D5D0',
  };
}
