# Revue visuelle — passe 2

Passe réalisée sur `feat/NW-map-style`, sans commit ni push. La référence `reference/nowave-target.png.png` a été inspectée avant modification. Les comparatifs utilisent exactement les mêmes centres, zooms et dimensions (960 × 850).

## Améliorations obtenues

La bathymétrie fictive présente des bancs asymétriques, des transitions plus souples et davantage de variations dans les faibles profondeurs. Les structures au large restent plus calmes. Les courbes supplémentaires suivent ce même modelé, avec des traits fins et une hiérarchie de valeurs adaptée au zoom.

Les côtes et îlots ont des anses et irrégularités plus variées. Les textures des hauts-fonds et des récifs sont différenciées et restent sous les terres. Les ports, phares, ancres, épaves et bouées gagnent des détails distinctifs et une meilleure cohérence graphique, sans multiplier les objets. La palette terrestre est conservée.

## Évaluation des six vues

| Vue | Avant | Après | Évaluation visuelle |
| --- | --- | --- | --- |
| Globale | [Capture](previews/pass-2-before/01-global.png) | [Capture](previews/final-style/01-global.png) | Structure marine plus présente, grandes transitions plus élégantes, moins de chiffres concurrents ; nom de mer plus affirmé. |
| Régionale | [Capture](previews/pass-2-before/02-regional.png) | [Capture](previews/final-style/02-regional.png) | Plateaux côtiers et gradients mieux articulés ; côtes plus organiques, hiérarchie préservée. |
| Côtière | [Capture](previews/pass-2-before/03-coastal.png) | [Capture](previews/final-style/03-coastal.png) | Faibles profondeurs et courbes plus expressives ; bouées, phares et mouillages plus reconnaissables. |
| Marina | [Capture](previews/pass-2-before/04-marina.png) | [Capture](previews/final-style/04-marina.png) | Digue extérieure plus souple, pontons mieux contrastés, entrée rouge/verte lisible ; bassins et circulation restent clairs. |
| Dangers | [Capture](previews/pass-2-before/05-dangers.png) | [Capture](previews/final-style/05-dangers.png) | Amélioration la plus nette : bancs modelés, chenal plus profond, grains des hauts-fonds et fragments de récif distincts, épave rouge détourée très lisible. |
| Réserve | [Capture](previews/pass-2-before/06-reserve.png) | [Capture](previews/final-style/06-reserve.png) | Contour plus doux et label mieux intégré ; zone discrète, lecture bathymétrique conservée. |

Limites visuelles : la géographie reste une composition fictive. Certains raccords de courbes demeurent perceptibles à fort zoom et la marina conserve des bassins géométriques. Le rendu est affiné, sans prétendre reproduire toute la richesse de la maquette.

## Vérifications

| Contrôle | Résultat |
| --- | --- |
| Génération des assets puis du style | Réussie ; `build_style.py` reste la source de vérité du style. |
| `npm test --prefix cartography` | Styles MapLibre v8 valides : 61 / 59 / 4 couches selon le mode. |
| Tests Python existants | 7 réussis. |
| `flutter analyze` | Aucun problème. |
| `flutter test` | 6 réussis. |
| `flutter build web --release` | Build JavaScript réussi. Le dry-run Wasm optionnel a rencontré un crash natif Dart ; la validation ne couvre donc pas un build Wasm. |
| `npm run test:visual` | Six captures régénérées, pan/zoom actifs ; aucune erreur JavaScript ou MapLibre ; 161 réponses DEM HTTP 200. |
| `npm run test:web` | Test mobile Chromium réussi ; 38 réponses DEM HTTP 200, aucune erreur. |
| `npm run test:relief` | Marseille, Cassis et La Ciotat contrôlés ; 116 réponses DEM, aucune erreur. 815 760 pixels de mer comparés : aucun modifié par le hillshade. |
| `git diff --check` | Réussi, aucune sortie. |

Le fichier Flutter et son chargement CDN, le serveur, la source Mapzen, la couche hillshade et le masque de mer réel sont inchangés par rapport au début de cette passe (comparaison des contenus et empreintes). Le bandeau réel/fictif reste présent.

## Fichiers de cette passe

Inventaire calculé par comparaison SHA-256 avec l'état initial de la passe ; les changements des travaux précédents ne sont pas inclus ici.

- `cartography/assets/demo-bathymetry.png`
- `cartography/assets/demo-sea-mask.png`
- `cartography/assets/sprite.png`
- `cartography/assets/sprite@2x.png`
- `cartography/data/demo.geojson`
- `cartography/previews/final-style/01-global.png`
- `cartography/previews/final-style/02-regional.png`
- `cartography/previews/final-style/03-coastal.png`
- `cartography/previews/final-style/04-marina.png`
- `cartography/previews/final-style/05-dangers.png`
- `cartography/previews/final-style/06-reserve.png`
- `cartography/previews/final-style/browser-result.json`
- `cartography/previews/pass-2-before/01-global.png` (nouveau)
- `cartography/previews/pass-2-before/02-regional.png` (nouveau)
- `cartography/previews/pass-2-before/03-coastal.png` (nouveau)
- `cartography/previews/pass-2-before/04-marina.png` (nouveau)
- `cartography/previews/pass-2-before/05-dangers.png` (nouveau)
- `cartography/previews/pass-2-before/06-reserve.png` (nouveau)
- `cartography/style.json`
- `cartography/tools/build_style.py`
- `cartography/tools/generate_demo.py`
- `cartography/VISUAL_REVIEW_PASS_2.md` (nouveau rapport)

## État Git final

Les sorties ci-dessous sont cumulatives par rapport à HEAD : elles comprennent les travaux Mapzen et la première passe déjà présents au début. `git diff --stat` exclut les fichiers non suivis.

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
?? cartography/MAPZEN_REVIEW.md
?? cartography/VISUAL_REVIEW.md
?? cartography/VISUAL_REVIEW_PASS_2.md
?? cartography/assets/demo-sea-mask.png
?? cartography/assets/mapzen-attribution.html
?? cartography/assets/mapzen-preview-sea-mask.json
?? cartography/assets/mapzen-preview-sea-mask.png
?? cartography/data/glo90/
?? cartography/previews/final-style/
?? cartography/previews/mapzen/
?? cartography/previews/pass-2-before/
?? cartography/reference/
?? cartography/tests/test_relief.py
?? cartography/tools/browser_final_style.cjs
?? cartography/tools/browser_observe.cjs
?? cartography/tools/browser_relief.cjs
?? cartography/tools/check_relief_pixels.py
?? cartography/tools/prepare_relief_masks.py
?? map_poc/MapLibreJsSource.configured
```

### `git diff --check`

Aucune sortie, code de retour 0.

### `git diff --stat`

```
 cartography/.dockerignore              |    3 +-
 cartography/DATA_CONTRACT.md           |   15 +-
 cartography/Dockerfile                 |    1 +
 cartography/README.md                  |  189 ++++-
 cartography/assets/README.md           |   15 +-
 cartography/assets/demo-bathymetry.png |  Bin 182612 -> 409222 bytes
 cartography/assets/demo-relief.png     |  Bin 20052 -> 0 bytes
 cartography/assets/sprite.json         |  113 ++-
 cartography/assets/sprite.png          |  Bin 56429 -> 65976 bytes
 cartography/assets/sprite@2x.json      |  113 ++-
 cartography/assets/sprite@2x.png       |  Bin 18775 -> 19282 bytes
 cartography/data/demo.geojson          |    2 +-
 cartography/package.json               |    4 +-
 cartography/requirements.txt           |    1 +
 cartography/server.py                  |   62 +-
 cartography/style.json                 | 1243 +++++++++++++++++++++++---------
 cartography/tools/browser_smoke.cjs    |   19 +-
 cartography/tools/build_style.py       |  146 +++-
 cartography/tools/generate_demo.py     |  348 +++++++--
 cartography/tools/validate_style.cjs   |    7 +-
 map_poc/README.md                      |   11 +-
 map_poc/lib/main.dart                  |   11 +-
 map_poc/lib/map_style.dart             |   28 +-
 map_poc/test/map_style_test.dart       |   45 +-
 24 files changed, 1787 insertions(+), 589 deletions(-)
```
