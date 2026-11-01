# Sources et licences

Le [registre des sources](https://api.no-wave.fr/api/v1/map/marine-sources) donne les produits, DOI, liens de licence et limites des données marines.

## Crédits des données

- GEBCO Bathymetric Compilation Group 2026, *The GEBCO_2026 Grid* : domaine public, conditions GEBCO ; fond échantillonné et recoloré par NoWave.
- EMODnet Bathymetry Consortium, *EMODnet Digital Bathymetry (DTM 2024)* et contours 2022, produit UE : CC BY 4.0 ; sélection, conversion de signe, arrondi et transformations NoWave.
- Shom, Balisage maritime et levés bathymétriques archivés : Licence Ouverte 2.0.
- Shom, Épaves et obstructions 2022 : CC BY-SA 4.0 ; transformations NoWave.
- © IGN, BD TOPO, édition WFS 2026-06-15 : Licence Ouverte 2.0 ; transformations NoWave.
- NOAA Office of Coast Survey, ENC Direct to GIS : CC0 1.0.
- © Open Waters: Seamap : CC BY 4.0 ; données OpenStreetMap sous ODbL 1.0.
- © OpenStreetMap contributors, Shortbread et données OSM : ODbL 1.0 ; transformations NoWave.

Conserver les crédits visibles, les liens de licence et la mention des transformations lors d'une redistribution. La base dérivée contenant OSM reste sous ODbL ; les dérivés des épaves et obstructions Shom restent sous CC BY-SA 4.0.

Les services OSM demandent un cache d'au moins sept jours, un User-Agent joignable et aucun téléchargement massif ou préchargement hors ligne.

## Données de test

Les extraits de `backend/tests/fixtures/marine/` conservent les crédits et licences des fournisseurs ci-dessus. `port-merge.json` associe IGN et OSM ; `hydrography-real.json` réunit NOAA, Shom sous CC BY-SA 4.0 et EMODnet sous CC BY 4.0.

## Anciens dessins d'icônes

Le SVG historique des bouées vient de Temaki, sous [CC0](../mobile/assets/icons/buoys/LICENSE-Temaki.md). Les anciens dessins géométriques des aides fixes sont aussi sous [CC0](../mobile/assets/icons/fixed-aids/LICENSE-CC0.md).

Ces licences concernent les anciens dessins ; elles ne définissent pas la licence des PNG NoWave actuels.
