# Revue du port pilote Cassis réel

Travail sur `feat/NW-map-style`, sans commit, push, merge ou modification de `dev`.
La scène Cassis est supplémentaire. Le style DEMO, ses assets et les six captures
DEMO sont inchangés par comparaison SHA-256 avec le début de cette demande.
Le fichier Flutter `main.dart` et son chargement CDN sont également inchangés.
La source DEM et les propriétés de hillshade sont identiques au style approuvé.

## Lancement

```bash
python3 cartography/server.py --real-cassis
```

Le POC utilise la même URL locale de style qu'auparavant. Voir
[CASSIS_REAL.md](CASSIS_REAL.md) pour la récupération reproductible, les licences,
les unités, le référentiel vertical et les commandes Flutter.

## REAL et DEMO

| Catégorie | CASSIS_REAL | Scènes graphiques DEMO conservées |
| --- | --- | --- |
| Relief terrestre | Réel Mapzen/AWS, source et rendu inchangés | Même DEM externe réel ; île fictive opaque |
| Côte / masque marin | Réels OSM, géométries vectorielles | Géométrie synthétique propre à la démo |
| Bathymétrie / isolignes | Réelles SHOM, dérivées du même champ et avec provenance de chaque partie | Champ synthétique de la passe graphique 2 |
| Port / pontons / feux | Données OSM réellement retournées et inspectées | Objets nautiques fictifs |
| Données absentes | Pas d'objets ajoutés ; profondeur indisponible en gris bleu | Sources DEMO jamais transférées à Cassis |

Aucune bathymétrie ou géométrie fictive n'entre dans `CASSIS_REAL`.
Les symboles sont les assets graphiques NoWave, pas des observations : seules les
positions/géométries/tags OSM déterminent les objets affichés.

## Sources effectivement utilisées

- [OpenStreetMap / ODbL](https://www.openstreetmap.org/copyright), via Overpass Kumi ; la première instance Overpass a renvoyé HTTP 406. Tags, identifiants, versions et dates OSM sont conservés. Le timestamp du snapshot est indiqué dans `data/cassis/manifest.json`.
- [SHOM HOMONIM Golfe du Lion–Côte d'Azur](https://diffusion.shom.fr/donnees/bathymerie/mnt-facade-gdl-ca-homonim.html), grille ZNEG WGS84/PBMA, 0,001° ; profondeur = −altitude, NoData exclu. Référence et licence dans [les métadonnées originales](data/cassis/homonim-metadata.xml).
- [SHOM S201300200](https://doi.org/10.17183/S201300200), acquisition 30/09/2007–12/07/2013, trois instruments lidar. XYZ longitude/latitude/profondeur positive sous LAT, ZH assimilé PBMA ; [métadonnées originales](data/cassis/survey-metadata.xml).
- [Mapzen Terrain Tiles / AWS](https://registry.opendata.aws/terrain-tiles/), Terrarium ; attributions complètes conservées dans le style et `assets/mapzen-attribution.html`.

OSM et SHOM sont crédités dans l'attribution de la source GeoJSON : les sources
MapLibre `image` ne permettent pas la propriété `attribution`. Les notices ODbL
et Licence Ouverte 2.0 restent distinctes.

## Couverture SHOM constatée

Les WFS des levés après 2005 puis 1990–2005 ont été interrogés. Les réponses sont
filtrées par intersection réelle des géométries, au-delà de leur simple bbox.
**Un levé récent intersecte le pilote : S201300200. Aucun levé 1990–2005
n'intersecte effectivement cette emprise.** Le résultat découpé est conservé dans
`data/cassis/survey-coverage.geojson`.

Le paquet contient 99 611 561 points ; seuls **896 940 points de Cassis** sont gardés, dont **802 306 sondes positives hors terre OSM**. Les négatifs terrestres ne deviennent pas des profondeurs.

Grille finale **325 × 390**, pas métrique voisin de **10 m**, après agrégation des sondes dans 34 424 cellules de 10 m. HOMONIM reste un repli **0,001° / ≈111 m**, sans fausse précision ; son usage est interdit dans la marina.

Dans l'emprise d'eau de la marina, **104 / 310 cellules** portent une profondeur interpolée sur les sondes (**33.5 %**). Les autres restent NoData. L'emprise du catalogue couvre la marina, mais les mesures réellement exploitables ne la remplissent donc pas.

La même grille finale sert à la coloration et aux isolignes. Elle distingue
0=indisponible, 1=HOMONIM, 2=levé. Interpolation uniquement dans un triangle de
mesures aux arêtes ≤40 m, à ≤20 m du point agrégé le plus proche, sans extrapolation.
Les courbes 2/5 m sont issues du levé, jamais du MNT régional. Le pas de sortie
10 m ne signifie pas une précision de mesure garantie de 10 m.

## Objets OSM réellement trouvés

| Type normalisé | Nombre dans le pilote |
| --- | --- |
| `breakwater` | 1 |
| `coast` | 12 |
| `light` | 2 |
| `pontoon` | 34 |
| `port` | 1 |
| `urban` | 155 |
| `vegetation` | 8 |

La marina est `way/11407276`. Dix des 34 pontons intersectent sa géométrie :
`30384270`, `76017469`, `76017474`, `76017476`, `76017477`, `76017478`,
`76017479`, `76017480`, `76017481`, `335369616`.
Les deux feux sont `node/1420666229` (vert) et `node/1420666230` (rouge).
Le seul ouvrage de la famille visuelle digue est réellement un **épi/groyne**
`way/1481322489` ; il ne constitue pas une observation `man_made=breakwater`.
Les digues/quais du port dont le contour est dans OSM se lisent comme terre/côte.

Objets absents sous leurs tags dédiés : `waterway=dock`, `man_made=quay`,
`man_made=breakwater`, bouées, balises, épaves, mouillages identifiés, géométrie
explicite de chenal/entrée. Ils ne sont pas inventés. L'entrée se lit à travers
la géométrie côtière et les positions des feux. Les autres seamarks retournés
mais non normalisés sont recensés dans `osm_not_rendered` du manifest.

## Vérification visuelle et captures

| Capture | Évaluation |
| --- | --- |
| [01 — approche](previews/cassis-real/01-cassis-approach.png) | Baie et côte réelle lisibles ; structure des profondeurs, courbes et faibles fonds cohérents avec la grille ; palette NoWave conservée. |
| [02 — port](previews/cassis-real/02-cassis-port.png) | Forme du bassin, digues terrestres, entrée, pontons et deux feux OSM visibles ; manque de couverture du bassin signalé en gris bleu. |
| [03 — marina](previews/cassis-real/03-cassis-marina-detail.png) | Pontons réellement mappés nets, côte vectorielle stable ; les petites zones mesurées ne remplissent pas artificiellement les parties inconnues. |

Les trois captures ont été inspectées visuellement après génération. Le littoral
ne repose plus sur le masque raster approximatif de l'ancien relief-preview.

## Tests finaux

| Contrôle | Résultat |
| --- | --- |
| Préparation Cassis avec cache, puis génération du style | Réussies ; aucun générateur DEMO exécuté ou changé |
| Tests Python cartography | 12 réussis |
| Validation MapLibre v8 | DEMO 61 / vectoriel+DEM 59 / relief-preview 4 / Cassis 61 couches valides |
| `flutter analyze` | Aucun problème |
| `flutter test` | 7 réussis |
| `flutter build web --release` | Réussi, dry-run Wasm réussi ; avertissement CupertinoIcons préexistant, non bloquant |
| Chromium / CDN réel | Chargement, déplacement, zoom réussis ; zéro erreur JS et MapLibre |
| Réseau Cassis | Les trois fichiers de carte locaux répondent HTTP 200 ; 24 réponses DEM HTTP 200 |
| Mer avec/sans hillshade | 365 901 pixels comparés, **0 modifié** ; 294 642 pixels terrestres changent, le relief est actif |
| `git diff --check` | Aucune sortie, retour 0 |

Le test de pixels exclut 2 px de bord côtier et 45 px de l'interface d'attribution,
qui change lors du masquage de la couche ; les pixels du fond marin sont comparés
strictement. Résultats complets : [browser-result.json](previews/cassis-real/browser-result.json)
et [pixel-check.json](previews/cassis-real/pixel-check.json).

## Performance et limites

- L'emprise est seulement Cassis : 5,515–5,555° E / 43,190–43,225° N. Aucun nouveau scénario Marseille, La Ciotat ou autre n'a été préparé.
- Le GeoJSON, le masque d'eau et le PNG chargés par Flutter totalisent **321 705 octets**, environ 314 Kio. Les 14 Mo de sondes compressées et la grille de travail restent des données de préparation, jamais des requêtes Flutter.
- Le fournisseur expose un paquet de levé indivisible. La préparation a transféré **845 989 700 octets** par HTTP Range ; seul le sous-ensemble Cassis est écrit. Ce transfert initial reste coûteux, contrairement au petit jeu servi par le POC. Le XYZ global de 2,73 Go n'a jamais été matérialisé.
- HOMONIM couvre les approches, mais pas des détails portuaires. Les raccords entre le levé et le repli régional peuvent être visibles. Les lacunes du bassin sont délibérément conservées et peuvent produire des limites de raster visibles à fort zoom.
- Les feux OSM reprennent une source NGA de 2010 et le texte libre du feu vert mentionne un autre port. Les tags originaux restent disponibles ; aucune actualité ou certification nautique n'est déduite de ces contributions.
- OSM peut omettre des quais/pontons. Les pontons surfaciques sont représentés par leur contour, sans inventer un axe. Les données de secteurs lumineux ne sont pas exploitées ici.
- Mapzen et le CDN nécessitent Internet. Android/iOS et build Wasm complet non testés ; la validation porte sur Flutter Web JavaScript dans Chromium.

**Ne pas utiliser NoWave pour la navigation officielle.**

## Fichiers modifiés par cette demande

La liste suivante compare les empreintes avec l'état initial de cette demande,
indépendamment des modifications non commitées des passes précédentes.

- `cartography/CASSIS_REAL.md` (nouveau)
- `cartography/CASSIS_REVIEW.md` (nouveau)
- `cartography/DATA_CONTRACT.md`
- `cartography/README.md`
- `cartography/assets/cassis-bathymetry.png` (nouveau)
- `cartography/cassis-style.json` (nouveau)
- `cartography/data/cassis/depth-grid.npz` (nouveau)
- `cartography/data/cassis/features.geojson` (nouveau)
- `cartography/data/cassis/homonim-metadata.xml` (nouveau)
- `cartography/data/cassis/manifest.json` (nouveau)
- `cartography/data/cassis/survey-coverage.geojson` (nouveau)
- `cartography/data/cassis/survey-metadata.xml` (nouveau)
- `cartography/data/cassis/survey-points.npz` (nouveau)
- `cartography/data/cassis/water.geojson` (nouveau)
- `cartography/package.json`
- `cartography/previews/cassis-real/01-cassis-approach.png` (nouveau)
- `cartography/previews/cassis-real/02-cassis-port.png` (nouveau)
- `cartography/previews/cassis-real/03-cassis-marina-detail.png` (nouveau)
- `cartography/previews/cassis-real/browser-result.json` (nouveau)
- `cartography/previews/cassis-real/pixel-check.json` (nouveau)
- `cartography/previews/cassis-real/sea-with-hillshade.png` (nouveau)
- `cartography/previews/cassis-real/sea-without-hillshade.png` (nouveau)
- `cartography/previews/cassis-real/water-screen.json` (nouveau)
- `cartography/requirements-cassis.txt` (nouveau)
- `cartography/server.py`
- `cartography/tests/test_cassis.py` (nouveau)
- `cartography/tools/browser_cassis.cjs` (nouveau)
- `cartography/tools/build_style.py`
- `cartography/tools/check_cassis_sea.py` (nouveau)
- `cartography/tools/prepare_cassis.py` (nouveau)
- `cartography/tools/validate_style.cjs`
- `map_poc/lib/map_style.dart`
- `map_poc/test/map_style_test.dart`

## État Git

Les commandes ci-dessous sont cumulatives par rapport à HEAD ; elles comprennent
les passes précédentes déjà présentes au début. Les assets nouveaux/non suivis
ne figurent pas dans `git diff --stat`. Aucun fichier n'a été ajouté à l'index.

### `git status -sb`

```
## feat/NW-map-style...origin/feat/NW-map-style
 M cartography/.dockerignore
 M cartography/DATA_CONTRACT.md
 M cartography/Dockerfile
 M cartography/README.md
 M cartography/assets/README.md
 M cartography/assets/demo-bathymetry.png
 D cartography/assets/demo-relief.png
 M cartography/assets/sprite.json
 M cartography/assets/sprite.png
 M cartography/assets/sprite@2x.json
 M cartography/assets/sprite@2x.png
 M cartography/data/demo.geojson
 M cartography/package.json
 M cartography/requirements.txt
 M cartography/server.py
 M cartography/style.json
 M cartography/tools/browser_smoke.cjs
 M cartography/tools/build_style.py
 M cartography/tools/generate_demo.py
 M cartography/tools/validate_style.cjs
 M map_poc/README.md
 M map_poc/lib/main.dart
 M map_poc/lib/map_style.dart
 M map_poc/test/map_style_test.dart
?? cartography/CASSIS_REAL.md
?? cartography/CASSIS_REVIEW.md
?? cartography/MAPZEN_REVIEW.md
?? cartography/VISUAL_REVIEW.md
?? cartography/VISUAL_REVIEW_PASS_2.md
?? cartography/assets/cassis-bathymetry.png
?? cartography/assets/demo-sea-mask.png
?? cartography/assets/mapzen-attribution.html
?? cartography/assets/mapzen-preview-sea-mask.json
?? cartography/assets/mapzen-preview-sea-mask.png
?? cartography/cassis-style.json
?? cartography/data/cassis/
?? cartography/data/glo90/
?? cartography/previews/cassis-real/
?? cartography/previews/final-style/
?? cartography/previews/mapzen/
?? cartography/previews/pass-2-before/
?? cartography/reference/
?? cartography/requirements-cassis.txt
?? cartography/tests/test_cassis.py
?? cartography/tests/test_relief.py
?? cartography/tools/browser_cassis.cjs
?? cartography/tools/browser_final_style.cjs
?? cartography/tools/browser_observe.cjs
?? cartography/tools/browser_relief.cjs
?? cartography/tools/check_cassis_sea.py
?? cartography/tools/check_relief_pixels.py
?? cartography/tools/prepare_cassis.py
?? cartography/tools/prepare_relief_masks.py
?? map_poc/MapLibreJsSource.configured
```

### `git diff --check`

Aucune sortie, retour 0.

### `git diff --stat`

```
 cartography/.dockerignore              |    3 +-
 cartography/DATA_CONTRACT.md           |   34 +-
 cartography/Dockerfile                 |    1 +
 cartography/README.md                  |  203 +++++-
 cartography/assets/README.md           |   15 +-
 cartography/assets/demo-bathymetry.png |  Bin 182612 -> 409222 bytes
 cartography/assets/demo-relief.png     |  Bin 20052 -> 0 bytes
 cartography/assets/sprite.json         |  113 ++-
 cartography/assets/sprite.png          |  Bin 56429 -> 65976 bytes
 cartography/assets/sprite@2x.json      |  113 ++-
 cartography/assets/sprite@2x.png       |  Bin 18775 -> 19282 bytes
 cartography/data/demo.geojson          |    2 +-
 cartography/package.json               |    5 +-
 cartography/requirements.txt           |    1 +
 cartography/server.py                  |   77 +-
 cartography/style.json                 | 1243 +++++++++++++++++++++++---------
 cartography/tools/browser_smoke.cjs    |   19 +-
 cartography/tools/build_style.py       |  191 ++++-
 cartography/tools/generate_demo.py     |  348 +++++++--
 cartography/tools/validate_style.cjs   |   10 +-
 map_poc/README.md                      |   11 +-
 map_poc/lib/main.dart                  |   11 +-
 map_poc/lib/map_style.dart             |   38 +-
 map_poc/test/map_style_test.dart       |   62 +-
 24 files changed, 1902 insertions(+), 598 deletions(-)
```
