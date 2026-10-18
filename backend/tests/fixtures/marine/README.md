Minimal real provider responses, fetched 2026-10-16 (longitude/latitude).

* `shom.json`: SHOM Balisage maritime, WFS 1.0 GetFeature, single
  `BALISAGE_BDD_WFS:{boycar,boylat,boysaw,boyspp,bcncar,topmar}`;
  bbox `5.85,43.04,6.0,43.15`, EPSG:4326, outputFormat=json.
  [Dataset / Licence Ouverte 2.0](https://diffusion.shom.fr/donnees/balisage_maritime.html).
  Attribution: Shom, https://dx.doi.org/10.17183/DOI_BALISAGE_MARITIME.
  Only sample features and their linked topmarks retained. `bcncar`, initially
  diagnostic, is now included in the fixed-aid extension; it remains outside the buoy renderer.
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


`fixed-aids.json`: real SHOM WFS excerpts (`bcncar`, `bcnlat`, `bcnspp`,
`lights`, `lndmrk`) for bbox 5.85,43.04,6.0,43.15, and NOAA ENC Direct
`enc_harbour/MapServer/{1,11,26}/query`, bbox -80.3,25.6,-80.05,25.9,
fetched 2026-10-17 with the same GeoJSON/CRS84 parameters described above.
SHOM Licence Ouverte 2.0 / DOI BALISAGE_MARITIME; NOAA ENC CC0 1.0.
Contains qualified Cape Cépet / Cape Florida tower-light-support examples,
a non-lighthouse landmark, actual IALA B green-port/red-starboard beacons,
and raw light attributes. No coordinates or nautical attributes invented.
The encoder unit test explicitly relocates a copy into its tile solely to
isolate encoding; that copy is never an integration fixture or display data.

Sparse classes additionally checked 2026-10-17: SHOM `bcnisd` GetFeature
maxFeatures=1 without bbox (Caye Ronde, Martinique) and NOAA harbour layer 2
query resultRecordCount=1 without envelope (Buttonwood Harbor). The same licences
apply. These real excerpts validate isolated-danger / safe-water semantics even
though those fixed classes are absent from the four local validation tiles.

`hydrography-real.json` : extraits publics réels du 17 octobre 2026 : NOAA ENC
harbour (104,76,34,36,33,99,156,158), Shom EPAVES_BDD_WFS (wrecks, obstrn),
EMODnet WFS emodnet:contours. NOAA CC0; Shom épaves/obstructions CC BY-SA 4.0;
EMODnet produit UE CC BY 4.0. Métadonnées/limites et requêtes reproductibles dans
`docs/architecture/hydrography.md`. Les cas synthétiques restent dans les tests
Python; ce fichier n'est pas une injection de données dans le runtime.

## Littoral et audit des aides — 18 octobre 2026

`coastline-real.json` conserve les polygones `ocean` décodés des tuiles OSM
Shortbread 6/33/23, 9/264/187 et 12/2116/1503, collectées pour cette correction.
Coordonnées MVT locales, axe Y vers le nord, extent publié conservé. Données
© OpenStreetMap contributors, ODbL 1.0 ; schéma Shortbread. Aucun champ de
profondeur n'est créé. Les réponses complètes restent dans les preuves locales.

`seamarks-coast-audit.json` contient 22 objets officiels réellement reçus pendant
l'audit (SHOM Balisage, Licence Ouverte 2.0 ; NOAA ENC Direct, registre CC0 1.0).
Chaque entrée garde le feature original, sa zone, son dataset et les propriétés
normalisées attendues. Les tests conservent leur géométrie jusqu'au MVT.
