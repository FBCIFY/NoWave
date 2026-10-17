Minimal real provider responses, fetched 2026-10-16 (longitude/latitude).

* `shom.json`: SHOM Balisage maritime, WFS 1.0 GetFeature, single
  `BALISAGE_BDD_WFS:{boycar,boylat,boysaw,boyspp,bcncar,topmar}`;
  bbox `5.85,43.04,6.0,43.15`, EPSG:4326, outputFormat=json.
  [Dataset / Licence Ouverte 2.0](https://diffusion.shom.fr/donnees/balisage_maritime.html).
  Attribution: Shom, https://dx.doi.org/10.17183/DOI_BALISAGE_MARITIME.
  Only sample features and their linked topmarks retained. `bcncar` is diagnostic,
  excluded from the production output and mobile rendering.
* `noaa.json`: NOAA ENC Direct, `enc_harbour/MapServer/{6,138}/query`,
  f=geojson, bbox `-80.2,25.73,-80.1,25.83`, outSR=4326, outFields=*.
  [Dataset / CC0](https://repository.library.noaa.gov/view/noaa/71555).
  Two real buoy and shoreline-construction features retained.

The fixtures are display data, not for navigation. Tests make no network calls.
* `ign.json`: IGN BD TOPO, WFS 2.0 `BDTOPO_V3:construction_lineaire`,
  CRS84, filter `nature='Quai' AND BBOX(geometrie,5.85,43.04,6,43.15,'CRS:84')`.
  Five real examples selected by detailed nature; the original 3D coordinates
  are retained in the fixture. [Licence Ouverte 2.0 / dataset](https://www.data.gouv.fr/datasets/bd-topo-r).
  Attribution: © IGN, BD TOPO, édition WFS 2026-06-15. Not for navigation.
* `openwaters.pbf`: minimal transformed fixture from
  `https://tiles.openwaters.io/seamap/12/2115/1503.pbf`; one real feature per available
  buoy class plus a fixed cardinal beacon to test exclusion. Re-encoded with the
  original tile-local coordinates, extent 4096, decoder y-up convention.
  © Open Waters: Seamap, CC BY 4.0; © OpenStreetMap contributors, ODbL.
* `shortbread.pbf`: minimal transformed fixture from
  `https://vector.openstreetmap.org/shortbread_v1/12/2115/1503.mvt`; one feature per
  available `kind` in the three port layers, same coordinates/extent convention.
  © OpenStreetMap contributors, ODbL. These are test fixtures of already requested
  display tiles, not an archive or a tile prefetch job.

`port-merge.json` conserve quatre couples de géométries réelles normalisées,
interrogées le 16 octobre 2026 (tuile 12/2115/1503), IGN BD TOPO WFS / OSM Shortbread.
Les URLs, licences et attributions sont celles des fixtures IGN et Shortbread
ci-dessus : © IGN BD TOPO édition WFS 2026-06-15, Licence Ouverte 2.0 ;
© OpenStreetMap contributors, ODbL 1.0. Les coordonnées WGS84 résultent uniquement
du décodage MVT/GeoJSON et du retrait de l'altitude IGN. Les IDs Shortbread désignent
des fragments de tuile. Le test vérifie ces correspondances de haute confiance et
la conservation de la géométrie officielle avec les deux provenances.
