import 'dart:convert';

import '../../../core/api/api_config.dart';

/// Contrat public de données marines NoWave. La position GPS n'intervient pas.
/// Toutes les familles partagent le backend des services applicatifs.
class MarineTiles {
  static String template(
    String family, {
    String apiBaseUrl = ApiConfig.baseUrl,
    Map<String, String> queryParameters = const {},
  }) => ApiConfig.tileTemplate(
    family,
    baseUrl: apiBaseUrl,
    queryParameters: queryParameters,
  );

  // Ensemble des sources susceptibles de contribuer aux tuiles. Les sources
  // effectives et leurs identifiants restent dans les propriétés de chaque objet.
  // URLs XYZ directes : le SDK ne remplace pas ces crédits par un TileJSON.
  // Le menu natif Mapbox extrait les liens HTML et omet le texte libre.
  static String attribution({String apiBaseUrl = ApiConfig.baseUrl}) =>
      '<a href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(ApiConfig.endpoint('api/v1/map/marine-sources', baseUrl: apiBaseUrl))}">'
      'Données transformées par NoWave · Ne pas utiliser pour la navigation</a> · '
      '<a href="https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1">'
      'EMODnet Bathymetry Consortium (2024), EMODnet Digital Bathymetry (DTM 2024) · '
      'profondeurs modélisées en mètres / LAT · sélection et arrondi NoWave</a> '
      '(<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>) · '
      '<a href="https://emodnet.ec.europa.eu/en/bathymetry">'
      'EMODnet Bathymetry · produit UE · contours DTM généralisés 2022</a> '
      '(<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>) · '
      '<a href="https://dx.doi.org/10.17183/LEVES_BATHY">Shom, Levés bathymétriques · acquisition 2005–2013 · archivés, hors chiffres du MVP</a> '
      '(<a href="https://www.etalab.gouv.fr/licence-ouverte-open-licence/">Licence Ouverte 2.0</a>) · '
      '<a href="https://dx.doi.org/10.17183/EPAVES_OBSTRUCTIONS">Shom, Épaves et obstructions 2022</a> '
      '(<a href="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA 4.0</a>) · '
      '<a href="https://www.data.gouv.fr/datasets/bd-topo-r">'
      '© IGN, BD TOPO, édition WFS 2026-06-15</a> · '
      '<a href="https://diffusion.shom.fr/donnees/balisage_maritime.html">'
      'Shom, Balisage maritime</a> '
      '(<a href="https://dx.doi.org/10.17183/DOI_BALISAGE_MARITIME">DOI</a>, '
      '<a href="https://www.etalab.gouv.fr/wp-content/uploads/2017/04/ETALAB-Licence-Ouverte-v2.0.pdf">'
      'Licence Ouverte 2.0</a>) · '
      '<a href="https://nauticalcharts.noaa.gov/data/gis-data-and-services.html">'
      'NOAA ENC Direct</a> · '
      '© <a href="https://openwaters.io/charts/seamap">Open Waters: Seamap</a> '
      '(<a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>) · '
      '© <a href="https://www.openstreetmap.org/copyright">'
      'OpenStreetMap contributors</a> '
      '(<a href="https://opendatacommons.org/licenses/odbl/1-0/">ODbL</a>)';
}
