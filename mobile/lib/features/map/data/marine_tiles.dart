import '../../../core/api/api_config.dart';

/// Contrat public de données marines NoWave. La position GPS n'intervient pas.
/// Un backend local peut être choisi sans déplacer l'API des signalements.
class MarineTiles {
  static const baseUrl = String.fromEnvironment(
    'MARINE_API_BASE_URL',
    defaultValue: ApiConfig.baseUrl,
  );

  static String get _root => baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

  static String template(String family) =>
      '${_root}api/v1/map/$family/{z}/{x}/{y}.pbf';

  // Ensemble des sources susceptibles de contribuer aux tuiles. Les sources
  // effectives et leurs identifiants restent dans les propriétés de chaque objet.
  // URLs XYZ directes : le SDK ne remplace pas ces crédits par un TileJSON.
  // Le menu natif Mapbox extrait les liens HTML et omet le texte libre.
  static final attribution =
      '<a href="${_root}api/v1/map/marine-sources">'
      'Données transformées par NoWave · Ne pas utiliser pour la navigation</a> · '
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
