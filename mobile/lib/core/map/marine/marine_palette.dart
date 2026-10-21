/// Palette cartographique : terres naturelles et océan bleu profond.
/// Partagée entre le style initial et sa réinstallation après un reload.
class MarinePalette {
  static const water = '#002D51';
  static const forest = '#395B32';
  static const scrub = '#627545';
  static const vegetation = '#7C8950';
  static const crop = '#A39F6B';
  static const snow = '#ECEDE5';

  static const basemapConfig = <String, Object>{
    'lightPreset': 'day',
    'theme': 'faded',
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
    'colorPlaceLabels': '#3A4843',
    'colorAdminBoundaries': '#CED1C8',
    'colorWater': water,
    'showRoadLabels': false,
    'showPointOfInterestLabels': false,
    'showTransitLabels': false,
    'showAdminBoundaries': false,
    'show3dObjects': false,
  };
}
