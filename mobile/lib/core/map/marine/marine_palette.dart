/// Palette validée : terre méditerranéenne douce, mer au premier plan.
/// Partagée entre le style initial et sa réinstallation après un reload.
class MarinePalette {
  static const water = '#E6F7FD';

  static const basemapConfig = <String, Object>{
    'lightPreset': 'day',
    'theme': 'faded',
    'colorLand': '#E8E0CC',
    'colorGreenspace': '#C1D0AF',
    'colorCommercial': '#E6E1D6',
    'colorEducation': '#E6E1D6',
    'colorMedical': '#E6E1D6',
    'colorIndustrial': '#DEDDD3',
    'colorBuildings': '#DAD7CD',
    'colorMotorways': '#BEC7C7',
    'colorTrunks': '#C6CDCC',
    'colorRoads': '#D1D5D0',
    'colorPlaceLabels': '#52616A',
    'colorAdminBoundaries': '#CED1C8',
    'colorWater': water,
    'showRoadLabels': false,
    'showPointOfInterestLabels': false,
    'showTransitLabels': false,
    'showAdminBoundaries': false,
    'show3dObjects': false,
  };
}
