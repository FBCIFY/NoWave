# Revue graphique du POC NoWave — 3 octobre 2026

Travail sur `feat/NW-map-style`, limité à `cartography/` et `map_poc/`.
Aucun commit, merge ou push. L'application métier et `dev` ne sont pas modifiés.
L'état Git décrit plus bas comprend aussi la passe Mapzen précédente, encore non commitée.

La référence a été inspectée **avant les modifications** : le fichier fourni est
`reference/nowave-target.png.png`, avec une double extension. Le chargement actif
`MapLibreJsSource.cdn()` a été conservé tel qu'il existait au début de cette passe.

## Changements techniques

- `tools/build_style.py` reste la source de vérité ; `style.json` est régénéré.
  61 couches en démo, 59 en vectoriel avec DEM et 4 dans l'aperçu réel.
- Palette bathymétrique demandée conservée. Champ continu fictif plus riche :
  plateaux peu profonds, hauts-fonds et petits îlots. Les courbes viennent du même
  champ, sont lissées sous la résolution de la grille puis simplifiées à environ 3 m.
  Courbes majeures d'abord, autres courbes et valeurs ensuite ; aucun sondage ponctuel.
- Terre ivoire/gris beige, végétation pâle, urbain discret ; trait de côte vectoriel
  fictif fin. Le port de démo possède une ouverture vers la mer, deux bassins,
  pontons à doigts, quais, digues, chenal et feux d'entrée.
- Cinq pictogrammes portuaires distincts sur disques colorés. Phares, feux,
  bouées IALA A et cardinales, mouillages, épave et rocher dangereux ; variantes
  de tour/monument/cheminée/pylône prévues dans le catalogue. Les identifiants et
  caractéristiques lumineuses apparaissent seulement de près. Ni portée ni hauteur.
- Réserve à remplissage turquoise transparent et contour discontinu.
  Parc éolien : **contour uniquement**, aucune couche de remplissage ni turbine.
- Hiérarchie des noms : mer, golfe, baie/rade, île/cap, ville, port, plage/anse/calanque.
  Les grandes étiquettes marines restent horizontales ; pas de géométrie de nom courbe.
- DEM Mapzen/AWS Terrarium 256 px inchangé ; hillshade z7=0, z10=0,15,
  z14=0,20, z18=0,22. La mer est recouverte par son propre raster, sans ombrage DEM.
  L'île fictive située dans l'océan reste plate ; son fond marin réel n'est pas
  présenté comme un relief terrestre. Le relief réel se teste séparément en France.
- NumPy 2.5.3 intervient uniquement dans le générateur d'assets (Pillow 12.3.0).
  Raster 2048 px, 0,6° de couverture, environ 33 m/pixel à l'équateur ; GeoJSON
  inférieur à 1 Mo. Aucun nouveau dataset géographique ou service cartographique.
- Les tests Chromium observent l'instance chargée par Flutter depuis le CDN,
  sans injecter une bibliothèque locale. Le serveur reste indépendant du backend métier.

## Six captures et comparaison à la référence

Les noms `final-style` sont ceux demandés pour le dossier de captures ; ils ne
constituent pas une certification de carte finale ou utilisable en navigation.
Positions en longitude/latitude, captures 960 × 850 avec barre et bandeau du POC.
La composition de cette petite scène requiert des zooms plus élevés que les panneaux
continentaux de la maquette : le panneau global de démo est à z10,8, pas à z4–6.

| Capture / caméra | CONFORME — sous-caractéristiques | PARTIELLEMENT CONFORME — différences restantes | MANQUANT |
|---|---|---|---|
| [01-global](previews/final-style/01-global.png) · 0,025 / 0,005 · z10,8 | Mer prioritaire, profondeur continue lisible, terre claire, grand nom marin, très peu de symboles. | Composition d'une île compacte ; davantage d'effet de bande claire au rivage que dans la référence. Quelques valeurs majeures et un phare restent visibles. | Géographie continentale et bathymétrie réelle permettant une composition équivalente à z4–6. |
| [02-regional](previews/final-style/02-regional.png) · 0,032 / 0,010 · z12 | Courbes majeures, premiers ports et phare, îlots et cap, noms côtiers secondaires. | Côte fictive moins découpée ; texture terrestre et nombre de toponymes plus pauvres. Les pictogrammes sont volontairement plus simples. | Relief terrestre sur cette île fictive ; données régionales réelles. |
| [03-coastal](previews/final-style/03-coastal.png) · 0,050 / 0,009 · z13,5 | Bouées, phare, feux, ancre, épave et hauts-fonds ; gradient côtier et courbes plus riches qu'en régional. | Répartition des bouées encore régulière car scène de catalogue ; feux et noms entrent progressivement et sont encore atténués à ce zoom. | Côte, objets et caractéristiques nautiques réels ; secteurs réels vérifiés. |
| [04-marina](previews/final-style/04-marina.png) · 0,037 / −0,0015 · z15,65 | Bassins, pontons à doigts, quais, digue, entrée, feux rouge/vert, pictogrammes portuaires et amarrage. | Plan rectangulaire très synthétique ; courbure des ouvrages et estran moins riches que la référence. Le bassin supérieur est partiellement cadré ; détails du bassin principal lisibles. | Géométrie et équipements d'une marina réelle, bâtiments côtiers qualifiés. |
| [05-dangers](previews/final-style/05-dangers.png) · 0,067 / 0,032 · z15 | Hauts-fonds clairs, contours cohérents, textures légères de récif/haut-fond, épave et rocher dangereux, îlots émergés. | Textures procédurales plus régulières, formes moins complexes que le panneau de référence. Les valeurs côtières peuvent encore être espacées davantage. | Récifs, estran et dangers observés, référentiel vertical réel. |
| [06-reserve](previews/final-style/06-reserve.png) · 0,0745 / 0,053 · z14,2 | Contour discontinu turquoise, remplissage faible, nom, îlots et bathymétrie visible dessous. | Réserve fictive plus compacte et moins géographique ; faible profondeur plus pâle que la mer du panneau de référence. | Périmètre légal et nom d'une réserve réelle. |

[Capture conservée avant cette passe](previews/final-style/before/demo.png) : état
historique de la démo, avec un autre cadrage ; ce n'est pas une comparaison pixel à pixel.
Les couples avant/après relief ci-dessous utilisent, eux, la même caméra.

## Contrôle visuel explicite

| Question | Résultat observé |
|---|---|
| Mer regardée avant la terre ? | Oui sur les vues globale, côtière, dangers et réserve ; le port met naturellement ses ouvrages au premier plan. |
| Faibles profondeurs immédiatement perceptibles ? | Oui, bandes claires et hauts-fonds détachés dans le dégradé. |
| Bleu différent compris comme profondeur différente ? | Oui, progression continue et légende cohérente. |
| Lecture au large ? | Oui, bleu profond sans noir et contours majeurs discrets. |
| Courbes visibles sans surcharge ? | Oui ; petites valeurs encore perfectibles dans les îlots. |
| Terre discrète ? | Oui, ivoire et végétation peu saturée, pas de petites rues. |
| Relief subtil ? | Oui dans les aperçus réels ; absent volontairement sur l'île fictive. |
| Littoral propre ? | Oui pour les vecteurs fictifs ; **non pour le littoral réel**, masque DEM temporaire encore pixelisé. |
| Symboles progressifs ? | Oui, contrôlé dans Chromium ; aucun symbole nautique à z4/6, bouées après z12. |
| Vue globale simple ? | Oui pour la scène fictive ; composition continentale à faible zoom encore non validable. |
| Vue côtière plus riche ? | Oui, bouées/feux/mouillages/dangers en plus. |
| Port nettement plus détaillé ? | Oui, pontons à doigts, bassins, quais et entrée. |
| Impression maritime immédiate ? | Oui : gradient bleu, profondeurs, balisage et pictogrammes portuaires. |

## REAL / DEMO / MISSING

**REAL** : Mapzen Terrain Tiles / Tilezen sur
[AWS Open Data](https://registry.opendata.aws/terrain-tiles/), endpoint
`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`.
Format Terrarium, source MapLibre `raster-dem`, tuiles 256 px, maxzoom 15.
Couverture globale composite ; résolution native et producteurs variables selon la
région. Le masque de diagnostic local est dérivé de 25 tuiles z12 et ne représente
pas un littoral levé. Les crédits des producteurs et leurs conditions propres sont
reproduits dans [mapzen-attribution.html](assets/mapzen-attribution.html), depuis
[Tilezen/Joerd](https://github.com/tilezen/joerd/blob/master/docs/attribution.md).
Le style expose cette attribution et son lien dans la carte.
Aucune clé API ni aucun compte AWS requis ; les tuiles sont chargées par Internet.
Le chargement Web utilise aussi le CDN MapLibre actuel, ainsi que les ressources
Flutter du build standard : ce POC n'est pas totalement hors ligne.
La substitution future du DEM se fait par `relief_source` ou `--relief-tiles` /
`--relief-attribution` en conservant les couches et le format Terrarium ; un GLO-90
ou SRTM brut nécessiterait une préparation préalable.

**DEMO** : toutes les profondeurs, courbes, terres/îlots, noms, végétation, urbanisation,
route, infrastructures portuaires, balisage, feux/caractéristiques/secteur, mouillages,
dangers et zones de la scène 0°/0°. Chaque feature possède `demo=true` ; bandeau
explicite conservé. Pictogrammes et textures : dessins originaux NoWave.
Aucune donnée fictive n'a été déplacée silencieusement sur Marseille/Cassis.

**MISSING** : littoral réel précis, bathymétrie côtière réelle, toponymie et objets
nautiques vérifiés, ports réels, estran qualifié, secteurs lumineux réels, limites
réglementaires sourcées. Les fichiers de recherche GLO-90 déjà présents ne sont pas
utilisés comme une source de relief livrée.

## Vérification Marseille / Cassis / La Ciotat

Aperçus de relief réel, mer unie, aucun objet nautique ni bathymétrie de démo :

| Zone | Avant / après hillshade | Pixels de mer opaque contrôlés | Modifiés |
|---|---|---:|---:|
| Cassis · 5,53 / 43,205 · z12 | [avant](previews/mapzen/cassis-before.png) / [après](previews/mapzen/cassis-after.png) | 204878 | 0 |
| La Ciotat · 5,605 / 43,174 · z12 | [avant](previews/mapzen/la-ciotat-before.png) / [après](previews/mapzen/la-ciotat-after.png) | 366780 | 0 |
| Marseille · 5,37 / 43,30 · z12 | [avant](previews/mapzen/marseille-before.png) / [après](previews/mapzen/marseille-after.png) | 244102 | 0 |

815760 pixels de mer opaque identiques ; relief visible sur les terres dans les trois
zones. La comparaison exclut la barre/bandeau et les 24 px du contrôle d'attribution,
qui change lorsque la source DEM est masquée. Elle ne certifie ni la position du
trait de côte ni les pixels partiellement transparents de sa bordure.
Le masque réel actuel **reste à remplacer** par un littoral suffisamment précis.
La bathymétrie réelle, la ville et les ouvrages de Marseille/Cassis sont absents :
ces captures ne valident que le relief, le masque et le contraste terre/mer.

Configuration reproductible :

```bash
python3 cartography/server.py --port 8767 --relief-preview --center 5.53 43.205 --zoom 12
# Pointer le POC vers http://127.0.0.1:8767/style.json avec NOWAVE_STYLE_URL.
# Marseille : --center 5.37 43.30 ; La Ciotat : --center 5.605 43.174
```

## Tests exécutés

| Commande / contrôle | Résultat |
|---|---|
| `generate_demo.py`, `build_style.py` | Réussite ; régénération successive contrôlée par SHA-256 sur style, GeoJSON, bathymétrie, masque et sprites. |
| `npm test --prefix cartography` | Styles MapLibre v8 valides : démo 61 couches, vectoriel + DEM 59, aperçu réel 4. |
| `python -m unittest discover -s cartography/tests -v` | 7 tests réussis : provenance, isolation des données, HTTP/MBTiles, DEM et masque. |
| `flutter analyze` | Aucun problème. |
| `flutter test` | 6 tests réussis. |
| `flutter build web --release` | Réussite ; avertissement CupertinoIcons du package MapLibre, sans échec de compilation. |
| `npm run test:web --prefix cartography` | Chromium 430 × 900, DPR 2 : carte affichée, symboles rendus, pan et molette actifs, aucune erreur JS/MapLibre ; 38 réponses DEM, toutes 200. |
| `npm run test:visual --prefix cartography` | Six scènes affichées, couches attendues présentes, captures produites ; pan/zoom, chargement DEM et progression de zoom vérifiés. Résultats dans le JSON ci-dessous. |
| `npm run test:relief --prefix cartography` | Cassis/La Ciotat/Marseille affichés ; 116 réponses DEM, toutes 200, aucune erreur JS/MapLibre, vérification de pixels réussie. |
| `git diff --check` | Réussite, aucune sortie. |

Preuves : [six scènes et zooms](previews/final-style/browser-result.json),
[DEM réel et erreurs](previews/mapzen/browser-result.json),
[comparaison des pixels](previews/mapzen/pixel-check.json).
SDK de test : Flutter 3.47.6 / Dart 3.13.5 ; Chromium headless avec WebGL logiciel.
Pas de test sur téléphone physique ni de mesure de fréquence d'images sur GPU mobile.

Les premières générations scalaires ont rencontré des erreurs/plantages natifs
intermittents de l'environnement. Après le calcul par tableaux, les générations
complètes et les contrôles de reproductibilité ont réussi. La cause native exacte
n'a pas été attribuée à un composant particulier.

## Limites et trois prochaines actions

La scène reste petite, synthétique et moins riche que la référence. Les silhouettes
nautiques sont simplifiées ; la géométrie des bassins et le placement régulier des
bouées restent des démonstrateurs. Les noms marins sont horizontaux. Les nouveaux
amers disposent de sprites mais pas de données réelles. Raster et textures doivent
être remplacés par des tuiles adaptées lorsqu'une zone réelle plus grande est intégrée.

1. Remplacer le masque côtier réel de diagnostic par une côte précise, puis vérifier
   le relief/mer à fort zoom sur Cassis et La Ciotat.
2. Brancher une bathymétrie réelle documentée sur la même palette et produire ses
   courbes depuis le même modèle, pour vérifier les approches Marseille/Cassis.
3. Qualifier les objets nautiques et ouvrages réels, affiner collisions/pictogrammes
   et mesurer le rendu sur téléphone physique, avant de traiter séparément
   l'auto-hébergement du chargement MapLibre.

## État Git avant tout commit

Les sorties ci-dessous incluent les changements de la passe DEM précédente.
Les entrées `data/glo90/*`, `reference/nowave-target.png.png` et
`map_poc/MapLibreJsSource.configured` préexistaient à cette intervention et sont
préservées. Le choix CDN était également déjà présent à son début.
`git diff --stat` ne compte pas les nouveaux fichiers non suivis.

Dernier test des six scènes : 161 réponses DEM, toutes 200 ; aucune erreur JS/MapLibre.
Zooms contrôlés : 4, 6, 9, 12, 14, 16, 18 ; pan et zoom fonctionnels.

### git status -sb

```text
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
?? cartography/MAPZEN_REVIEW.md
?? cartography/VISUAL_REVIEW.md
?? cartography/assets/demo-sea-mask.png
?? cartography/assets/mapzen-attribution.html
?? cartography/assets/mapzen-preview-sea-mask.json
?? cartography/assets/mapzen-preview-sea-mask.png
?? cartography/data/glo90/
?? cartography/previews/final-style/
?? cartography/previews/mapzen/
?? cartography/reference/
?? cartography/tests/test_relief.py
?? cartography/tools/browser_final_style.cjs
?? cartography/tools/browser_observe.cjs
?? cartography/tools/browser_relief.cjs
?? cartography/tools/check_relief_pixels.py
?? cartography/tools/prepare_relief_masks.py
?? map_poc/MapLibreJsSource.configured
```

### git diff --check

```text
(aucune sortie ; code 0)
```

### git diff --stat

```text
 cartography/.dockerignore              |    3 +-
 cartography/DATA_CONTRACT.md           |   15 +-
 cartography/Dockerfile                 |    1 +
 cartography/README.md                  |  189 +++++-
 cartography/assets/README.md           |   15 +-
 cartography/assets/demo-bathymetry.png |  Bin 182612 -> 274409 bytes
 cartography/assets/demo-relief.png     |  Bin 20052 -> 0 bytes
 cartography/assets/sprite.json         |  113 ++--
 cartography/assets/sprite.png          |  Bin 56429 -> 56605 bytes
 cartography/assets/sprite@2x.json      |  113 ++--
 cartography/assets/sprite@2x.png       |  Bin 18775 -> 14353 bytes
 cartography/data/demo.geojson          |    2 +-
 cartography/package.json               |    4 +-
 cartography/requirements.txt           |    1 +
 cartography/server.py                  |   62 +-
 cartography/style.json                 | 1083 +++++++++++++++++++++++---------
 cartography/tools/browser_smoke.cjs    |   19 +-
 cartography/tools/build_style.py       |  128 +++-
 cartography/tools/generate_demo.py     |  258 ++++++--
 cartography/tools/validate_style.cjs   |    7 +-
 map_poc/README.md                      |   11 +-
 map_poc/lib/main.dart                  |   11 +-
 map_poc/lib/map_style.dart             |   28 +-
 map_poc/test/map_style_test.dart       |   45 +-
 24 files changed, 1594 insertions(+), 514 deletions(-)
```

### Liste des fichiers suivis modifiés ou supprimés

```text
cartography/.dockerignore
cartography/DATA_CONTRACT.md
cartography/Dockerfile
cartography/README.md
cartography/assets/README.md
cartography/assets/demo-bathymetry.png
cartography/assets/demo-relief.png
cartography/assets/sprite.json
cartography/assets/sprite.png
cartography/assets/sprite@2x.json
cartography/assets/sprite@2x.png
cartography/data/demo.geojson
cartography/package.json
cartography/requirements.txt
cartography/server.py
cartography/style.json
cartography/tools/browser_smoke.cjs
cartography/tools/build_style.py
cartography/tools/generate_demo.py
cartography/tools/validate_style.cjs
map_poc/README.md
map_poc/lib/main.dart
map_poc/lib/map_style.dart
map_poc/test/map_style_test.dart
```

### Nouveaux fichiers et entrées préexistantes non suivies

```text
cartography/MAPZEN_REVIEW.md
cartography/VISUAL_REVIEW.md
cartography/assets/demo-sea-mask.png
cartography/assets/mapzen-attribution.html
cartography/assets/mapzen-preview-sea-mask.json
cartography/assets/mapzen-preview-sea-mask.png
cartography/data/glo90/glo90_2024_search.json
cartography/data/glo90/glo90_search.json
cartography/previews/final-style/01-global.png
cartography/previews/final-style/02-regional.png
cartography/previews/final-style/03-coastal.png
cartography/previews/final-style/04-marina.png
cartography/previews/final-style/05-dangers.png
cartography/previews/final-style/06-reserve.png
cartography/previews/final-style/README.md
cartography/previews/final-style/before/demo.png
cartography/previews/final-style/browser-result.json
cartography/previews/mapzen/README.md
cartography/previews/mapzen/browser-result.json
cartography/previews/mapzen/cassis-after.png
cartography/previews/mapzen/cassis-before.png
cartography/previews/mapzen/demo-after.png
cartography/previews/mapzen/la-ciotat-after.png
cartography/previews/mapzen/la-ciotat-before.png
cartography/previews/mapzen/marseille-after.png
cartography/previews/mapzen/marseille-before.png
cartography/previews/mapzen/pixel-check.json
cartography/reference/nowave-target.png.png
cartography/tests/test_relief.py
cartography/tools/browser_final_style.cjs
cartography/tools/browser_observe.cjs
cartography/tools/browser_relief.cjs
cartography/tools/check_relief_pixels.py
cartography/tools/prepare_relief_masks.py
map_poc/MapLibreJsSource.configured
```
