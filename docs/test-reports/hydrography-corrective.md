# Correction hydrographique — 17 octobre 2026

Travail local sur `feature/marine-bathymetry`, HEAD conservé `20437348`.
Le travail hydrographique déjà présent est conservé. Sauvegarde initiale :
`/tmp/nowave-hydro-corrective/initial-local-work.tar.gz` (29 fichiers).
Téléphone réel LGN LX1 `AV5PJV6328H03108`, Android 15/API35 ; backend8004,
reverse ADB8004 conservé. Aucun agent délégué, commit, push ou PR.

Les preuves sont dans [le dossier de captures et journaux](../../test-results/hydrography-corrective-2026-10-17/).
Les captures finales mentionnées ci-dessous ont été ouvertes visuellement.
Ce dossier de preuves est ignoré par Git ; il est conservé localement.

## A. Identification prouvée des losanges

Avant toute modification graphique : interrogation **native des features
réellement rendues** par Mapbox, sur la vue Toulon 5.925 E / 43.105 N / Z14.
21 résultats, dont les trois exemples ci-dessous, à des pixels visibles.
Source normalisée `shom`, source native `nowave-underwater-hazards`, source-layer
`underwater_hazard`, layer Flutter `nowave-hazard-points`.
L'expression native choisissait `nowave-hazard-obstruction` ; son image générée
était un losange avec point central. Ce ne sont pas des sondes ni des bouées.

Tous les `source_id` ci-dessous ont le préfixe `EPAVES_BDD_WFS:obstrn:`.

| Identifiant exact après ce préfixe | Objet décrit par la source | Type / catégorie / état | Géométrie rendue | Brassiage | Précision horizontale publiée | Pixel logique visible |
|---|---|---|---|---|---|---|
| `FR 0000140314 00001` | Ancre de la Direction du Port | obstruction / inconnue / inconnu | Point(5.9227198,43.1133549) | 11.8m | 0.7m | (126.87,135.83) |
| `FR 0000000263 00003` | Amas de débris divers | obstruction / inconnue / inconnu | Point(5.9211427,43.104974) | 12.3m | 1m | (90.12,403.33) |
| `FR 0000005394 00001` | Trépied métallique retourné | obstruction / inconnue / inconnu | Point(5.92206,43.101026) | 10.3m | 10m | (111.49,529.33) |

Pour chacun : `brassiage`, `inspireid`, `precis_bra`, `precis_loc`, `caract_obj`,
`latitude`, `longitude`, `long_obj`, `nom`, `circ_nauf` sont conservés dans
`source_attributes`. Qualification publiée : brassiage minimal connu ; aucune
catégorie détaillée ou exposition à la marée n'est déduite de cette profondeur.
Les coordonnées du rendu sont quantifiées par MVT ; les attributs source gardent
les positions publiées originales. Les références verticales des épaves Shom
restent zéro des cartes, définition locale non précisée par ce schéma.

Preuves complètes : [JSON du rendu avant correction](../../test-results/hydrography-corrective-2026-10-17/rendered-before.json)
et [capture avant correction](../../test-results/hydrography-corrective-2026-10-17/before-toulon.png).
Les mots mentionnant des petits rochers dans la description des débris ne
changent jamais leur famille officielle `obstrn`.

## B. Correction graphique

Roche : croix, avec variantes uniquement selon l'état WATLEV réellement publié.
Épave : coque et mât. Obstruction : petite enceinte ouverte interrompue avec un
trait central, plus discrète que le losange précédent. Famille inconnue : tiret
minuscule distinct d'une roche. Les familles ne partagent plus un même losange.
Les objets étendus gardent leur géométrie et un contour discret. Ni dangerosité,
ni profondeur, ni état couvrant/découvrant ne sont inventés.
Les images restent des symboles NoWave, sans prétention de certification INT1.

## C. Contours : texte, taille, répétition et collisions

`depth_label` provient exclusivement de la profondeur publiée normalisée en m.
3.6 reste 3.6 ; 1.25 reste 1.25 ; aucun arrondi systématique au décimètre.
Mapbox : `symbolPlacement=line`, spacing160 pixels logiques, rotation map,
texte à l'endroit, angle maximal70°, collisions natives activées. Texte sombre
#354D5B, halo .6px, sans boîte. La répétition donne plusieurs valeurs sur les
longues portions de ligne visibles, sans répéter une valeur à chaque sommet.

| Zoom | Taille logique |
|---|---|
| 12 | 10.5px |
| 13 | 11px |
| 14 | 11.5px |
| 15 | 12px |
| 16 | 12.5px |
| 17 | 13px |
| 18+ | 13.5px |

Comparaison réelle à Z12 : 9px, 12px, puis interpolation retenue 10.5px.
[9px](../../test-results/hydrography-corrective-2026-10-17/font-9.png),
[12px](../../test-results/hydrography-corrective-2026-10-17/font-12.png),
[10.5px](../../test-results/hydrography-corrective-2026-10-17/font-restore.png).
9px devient moins confortable ; à12px, les collisions ont supprimé tous les
labels du contour50m dans cette vue. La taille10.5px était lisible et plus stable.

Ce constat a conduit à un contrôle supplémentaire : seuls les IDs ayant un
chiffre effectivement placé dans le viewport par Mapbox activent l'opacité de
leur ligne (`feature-state.label_visible`). Une ligne trop courte ou sans aucun
label placé reste masquée. Le placement est relu après changement natif des
symboles et à l'arrêt de la carte. Les mouvements invalident l'ancien placement,
les réponses périmées sont rejetées, les erreurs masquent aussi les anciennes
lignes. Les labels ne sont pas forcés au-dessus des aides ou de l'interface.
Le contrat de tuile `?v=3` évite le cache antérieur dépourvu de `depth_label` et
recharge le catalogue corrigé pendant la mise à jour.

## D. EMODnet français

Contours publiés 2022, dérivés du DTM et généralisés au1:500000 : Z12–13 opacité
majeure .72/mineure .48 ; Z14 .32/.22 ; exclusion de la ligne **et du texte** dès
Z15. Les contours ENC NOAA restent éligibles aux zooms locaux. Les sondes Shom
ne servent pas à reconstruire des contours : aucune nouvelle courbe française
plus précise ne remplace EMODnet. La bathymétrie raster et la texture existantes
restent des fonds visuels ; aucune valeur n'en est extraite.

[Contour50m atténué à Z14](../../test-results/hydrography-corrective-2026-10-17/toulon-contour-z14.png),
[même secteur sans contour à Z16](../../test-results/hydrography-corrective-2026-10-17/emodnet-hidden-z16.png).
La requête native à Z16 retrouve zéro feature dans chacune des trois couches
de contours/labels ; [relevé JSON](../../test-results/hydrography-corrective-2026-10-17/emodnet-hidden-z16.json).

## E. Sondes françaises : recherche et intégration réelle

Le WFS `LEVES_BATHY_*` expose des emprises, pas des sondes. Recherche effectuée
sur les quatre périodes du catalogue : après2005,1990–2005,1970–1990,avant1970.
Le produit [Levés bathymétriques Shom](https://diffusion.shom.fr/leves-bathy.html)
et le [service public de prépaquets](https://api.data.shom.fr/support/en/node/43?q=en/node/43)
ont permis de télécharger les archives numériques, sans authentification.
L'URL fonctionnelle inclut `prepackage/{survey}/file/{survey}.7z`.
Les fichiers XYZ et leurs XML associés ont été réellement extraits et inspectés.
Licence Ouverte Etalab2.0, absence de restriction d'accès public dans les XML ;
attribution et DOI conservés et publiés dans le menu de la carte et l'API sources.

| Levé | Données réellement intégrées | Acquisition d'après l'archive |
|---|---|---|
| S201107800 | 214 lignes XYZ, fichier intégral | 2011–2013 |
| S200806500 | 203 lignes XYZ, fichier intégral | 2007–2008 |
| S200600700 | 13 lignes XYZ, fichier intégral | 2005 |
| S201300200 | 7365 lignes originales sélectionnées dans l'emprise Toulon | 2007–2013 |

**7795 observations originales**, couvrant des parties de la rade, des grands
bassins, du Vieux-Port, de Port Saint-Louis et des approches. Ce catalogue initial
est limité à Toulon, incomplet, et historique ; il ne représente pas tous les
ports français ni leur état actuel. Certaines zones restent sans mesures.

En-tête vérifié : longitude/latitude en degrés, profondeur en mètres positive
vers le bas, **LAT** explicite. Source normalisée `shom-surveys`, ID = levé +
numéro de ligne original. Profondeur et unité originales, datum, acquisition,
révision, source, licence, ligne XYZ et provenance par DOI/URL/SHA-256 sont gardés.
Aucune incertitude chiffrée par point n'est publiée ici : elle reste inconnue.
Les décimales affichées ne garantissent pas une précision centimétrique.

L'archive S201300200 vérifiée contient 99,611,561 observations (837,982,269 octets
compressés), dont 11,672 dans l'emprise5.88–5.96E /43.08–43.13N. Le fichier est
mixte lidar topo/bathy : les observations négatives sont exclues **avant** la
sélection du minimum pour cet import, afin d'écarter les observations terrestres.
Les profondeurs non négatives retenues existent déjà dans le fichier publié.
La grille conserve une ligne originale minimale par cellule Z16/32px, jamais un
centre de cellule ni une moyenne. Les trois autres fichiers ne sont pas réécrits.

Exemples vérifiables : S200806500 ligne4 : `5.9274025,43.1013295,2.8` ;
S201300200 ligne99229866 : `5.9319458,43.1189654,2.06` ;
S201300200 ligne99366673 : `5.9250913,43.1145063,12.49`.

[Manifeste et sommes de contrôle](../../backend/app/infrastructure/marine/data/shom-surveys/manifest.json),
[documentation de reproduction](../../backend/app/infrastructure/marine/data/shom-surveys/README.md),
[importeur hors ligne](../../backend/tools/import_shom_survey.py).
Le serveur utilise un index spatial du petit catalogue résultant ; aucune archive
massive n'est téléchargée ou parcourue pendant une requête de tuile. Les nombres
actuels du WFS d'emprises peuvent différer de ceux des archives : le catalogue
utilise les fichiers numériques vérifiés et leurs dates, pas une estimation du WFS.

## F. Sondes USA et densité

NOAA ENC Direct SOUNDG demeure la source américaine. Valeur Z publiée en mètres,
décimales préservées, découplée des contours et des dangers. Exemple réel Miami :
`harbour:76:14452593`,0.9m ; autres mesures0.3/1.2/15.2m visibles dans les chenaux.
Les champs VERDAT et sounding_datum absents dans les exemples inspectés restent
inconnus : aucun MLLW ou LAT n'est supposé pour ces points américains.

Grilles Mercator mondiales emboîtées, minimum puis précision publiée, priorité et
ID stable. Références incompatibles séparées ; les références inconnues de
cellules ENC/datasets différents ne sont pas fusionnées comme équivalentes.
Cartes `harbour`/`berthing` et levés côtiers : cellules64/32/32px à Z14/15/16.
Autres usages :128/64/64px. La distinction repose sur la source et son usage,
pas sur une frontière portuaire inventée. Le minimum retenu aux zooms grossiers
reste retenu aux zooms fins. Texte seul, taille adaptative, padding2px, collisions
actives, tri ascendant de profondeur. Z17 surzoome la source Z16 sans créer de
mesures supplémentaires. Les collisions résiduelles évitent la superposition.

## G. Validation Toulon

| Capture réelle ouverte | Constat |
|---|---|
| [Z11.9](../../test-results/hydrography-corrective-2026-10-17/toulon-z11.9.png) | Aucune nouvelle courbe ni sonde |
| [Z12](../../test-results/hydrography-corrective-2026-10-17/toulon-z12.png) | Courbes50/100m et chiffres visibles, dangers corrigés |
| [Z12 régional](../../test-results/hydrography-corrective-2026-10-17/toulon-regional-z12.png) | Répétition50/100/200m lisible |
| [Z14](../../test-results/hydrography-corrective-2026-10-17/toulon-z14.png) | Sondes réelles, obstructions discrètes, balisage prioritaire |
| [Z16 Tour Royale](../../test-results/hydrography-corrective-2026-10-17/toulon-z16.png) | Densité locale, décimales, aucune courbe EMODnet |
| [Z17 Saint-Louis](../../test-results/hydrography-corrective-2026-10-17/toulon-z17.png) | 0.73/1.05/1.19m notamment, sans pastilles |
| [Z17 grands bassins](../../test-results/hydrography-corrective-2026-10-17/toulon-grands-bassins-z17.png) | 11.67/12.49/12.58m notamment |
| [Z17 Vieux-Port](../../test-results/hydrography-corrective-2026-10-17/toulon-vieux-port-z17.png) | 2.06/3.2/4.82m notamment ; épaves et quais distincts |

Le pointage natif après correction et les propriétés source sont également
conservés dans les JSON de rendu. Les captures dont le zoom dérivait pendant une
manipulation de test ont été reprises ; le script vérifie le zoom avant capture.
Les affichages de faibles profondeurs près des ouvrages restent les observations
publiées, sans déduction d'état découvrant ou de dangerosité.

## H. Validation Miami / Cape Florida

[Z12 contours](../../test-results/hydrography-corrective-2026-10-17/miami-z12.png),
[Z14](../../test-results/hydrography-corrective-2026-10-17/miami-z14.png),
[Z15](../../test-results/hydrography-corrective-2026-10-17/miami-z15.png),
[Z16](../../test-results/hydrography-corrective-2026-10-17/miami-z16.png),
[Z17](../../test-results/hydrography-corrective-2026-10-17/miami-z17.png),
[Cape Florida Z14](../../test-results/hydrography-corrective-2026-10-17/cape-florida-z14.png),
[roche publiée Z16](../../test-results/hydrography-corrective-2026-10-17/miami-rock-z16.png).
La zone Fisherman's Channel/Port Miami permet une validation dense : les chiffres
restent séparés et sous les infrastructures/balises. Les contours1.8/3.6/5.4m ne
sont pas arrondis. Des roches, épaves et obstructions sont visibles dans la vue
régionale ; le contrôle détaillé de roche conserve son état publié.

## I. Tests et environnement de vérification

- Ruff backend : réussi.
- Pytest complet final : **743 passed**,1 avertissement Starlette existant,
  Python3.12 (version du Dockerfile), `PYTHONMALLOC=malloc`.
- Flutter : **485 tests réussis**, analyse sans problème.
- Format Dart :166 fichiers,0 modification.
- APK debug : construit avec les defines locaux réels (`.env.json`, backend8004
  et template bathymétrique local), installé sur le téléphone en conservant la session.
- Diff whitespace : contrôlé ; état final et sorties conservés à la sectionL.

Limitation de validation : des exécutions sans réglage d'allocateur ont rencontré
un `SystemError` ou un segfault dans `_blue_color_lut`, code bathymétrique
préexistant et inchangé, sous Python3.14 et une fois sous3.12. Plusieurs passages
complets ont réussi sous3.12 ; le dernier passage complet après les corrections
réussit avec `PYTHONMALLOC=malloc`. Cela ne constitue pas une correction démontrée
de ce défaut d'environnement. Les journaux de réussite et d'échec sont conservés.
Le premier lancement via l'exécutable nu pytest ne trouvait pas le package
`backend` ; les lancements complets utilisent `python -m pytest`.
L'import massif a été réalisé par awk/mawk après des échecs de lecture Python ;
les checksums, les comptes et les lignes originales contrôlent le résultat.

Les tests ajoutés couvrent les valeurs/labels/décimales, tailles de zoom, Z12,
spacing, collisions, visibilité couplée au vrai placement, réponses périmées,
échec natif, reload/idempotence, familles de dangers/fallback, atténuation EMODnet,
densité locale, minimum, datums distincts, import de lignes originales, exclusion
explicite des négatifs du levé mixte et provenance des7795 points officiels.

## J. Revue1

Diff suivi et fichiers hydrographiques nouveaux relus, en distinguant le travail
initial sauvegardé. Corrections issues de la revue : valeurs absentes sur les
contours, arrondi inutile des sondes, icône générique ambiguë, absence de fallback
inconnu, taille fixe, densité uniforme et précision EMODnet trompeuse à fort zoom.
Le test des tailles a révélé une courbe muette sous collision : ajout du couplage
entre ligne et label réellement placé, puis tests de concurrence/échec et
vérification native sur téléphone.

## K. Revue2

Relecture de la demande point par point et contrôle de la provenance numérique.
Corrections : traitement explicite du levé lidar mixte avant le minimum,
préservation du numéro de ligne original, index spatial pour éviter le parcours
du nuage en requête, cache mobile versionné, relance du placement après reload
et après changement de symboles, masquage en cas d'échec de la requête native.
Le reload natif a été effectué sur le téléphone puis `addTo` relancé deux fois :
3 sources,7 layers,8 images, aucun doublon.
[Preuve native](../../test-results/hydrography-corrective-2026-10-17/reload.json),
[capture Z12 après reload](../../test-results/hydrography-corrective-2026-10-17/after-reload-z12.png),
[style natif final](../../test-results/hydrography-corrective-2026-10-17/style-final.json).
La correspondance entre les lignes activées et les IDs de labels réellement placés
a été contrôlée après reload : [JSON natif](../../test-results/hydrography-corrective-2026-10-17/after-reload-rendered.json).
Les contrôles complets ont été relancés après ces corrections. Les aides fixes,
phares/feux, bouées×2/neutral noir/IALA, ports, GPS, badgeZ, halo, reports, texture
et recentrage ne font l'objet d'aucune modification fonctionnelle propre à eux.
Les ajouts à MapScreen installent l'hydrographie, isolent ses erreurs et suivent
le placement des labels. La hiérarchie BOTTOM/MIDDLE/TOP/reports/UI est conservée.
Les limites restantes sont explicites : catalogue français local et historique,
incertitude individuelle inconnue, datum américain absent dans certains objets,
instabilité des essais de LUT dans l'environnement Python local.

## L. Git final

Sorties finales ajoutées ci-dessous avant arrêt. Aucun commit, push ou PR.

```text
feature/marine-bathymetry
20437348 feat(map): add fixed aids lighthouses and marine lights

$ git status --short --untracked-files=all
 M backend/app/api/routes/map_tiles.py
 M backend/app/application/services/marine_merge.py
 M backend/app/application/services/marine_tiles.py
 M backend/app/domain/marine.py
 M backend/app/domain/marine_tile.py
 M backend/app/infrastructure/marine/encoding.py
 M backend/app/infrastructure/marine/http.py
 M backend/app/infrastructure/marine/providers.py
 M backend/app/infrastructure/marine/runtime.py
 M backend/app/infrastructure/marine/sources.py
 M backend/tests/api/test_marine_tiles.py
 M backend/tests/fixtures/marine/README.md
 M docs/architecture/marine-sources.md
 M mobile/lib/features/map/data/marine_tiles.dart
 M mobile/lib/features/map/presentation/map_screen.dart
 M mobile/test/features/map/presentation/buoy_source_error_test.dart
?? backend/app/domain/hydrography.py
?? backend/app/infrastructure/marine/data/hydro_layers.json
?? backend/app/infrastructure/marine/data/shom-surveys/.gitattributes
?? backend/app/infrastructure/marine/data/shom-surveys/README.md
?? backend/app/infrastructure/marine/data/shom-surveys/S200600700.xyz
?? backend/app/infrastructure/marine/data/shom-surveys/S200806500.xyz
?? backend/app/infrastructure/marine/data/shom-surveys/S201107800.xyz
?? backend/app/infrastructure/marine/data/shom-surveys/S201300200.jsonl
?? backend/app/infrastructure/marine/data/shom-surveys/manifest.json
?? backend/app/infrastructure/marine/hydro_encoding.py
?? backend/app/infrastructure/marine/hydro_normalization.py
?? backend/app/infrastructure/marine/hydro_providers.py
?? backend/app/infrastructure/marine/shom_soundings.py
?? backend/tests/fixtures/marine/hydrography-real.json
?? backend/tests/unit/test_hydrography.py
?? backend/tools/import_shom_survey.py
?? backend/tools/probe_hydrography.py
?? backend/tools/refresh_hydro_catalog.py
?? docs/architecture/hydrography.md
?? docs/test-reports/hydrography-corrective.md
?? docs/test-reports/hydrography.md
?? mobile/lib/features/map/data/hydrography_layer.dart
?? mobile/test/features/map/data/hydrography_layer_test.dart

$ git diff --stat
 backend/app/api/routes/map_tiles.py                | 27 +++++++++++++++
 backend/app/application/services/marine_merge.py   | 37 ++++++++++++++++++++-
 backend/app/application/services/marine_tiles.py   | 30 +++++++++++++++--
 backend/app/domain/marine.py                       |  7 +++-
 backend/app/domain/marine_tile.py                  |  2 +-
 backend/app/infrastructure/marine/encoding.py      | 20 ++++++++++--
 backend/app/infrastructure/marine/http.py          |  3 ++
 backend/app/infrastructure/marine/providers.py     |  4 ++-
 backend/app/infrastructure/marine/runtime.py       | 10 ++++++
 backend/app/infrastructure/marine/sources.py       | 38 +++++++++++++++++++++-
 backend/tests/api/test_marine_tiles.py             | 20 ++++++++++--
 backend/tests/fixtures/marine/README.md            |  7 ++++
 docs/architecture/marine-sources.md                |  7 ++++
 mobile/lib/features/map/data/marine_tiles.dart     |  7 ++++
 .../lib/features/map/presentation/map_screen.dart  | 27 ++++++++++++++-
 .../map/presentation/buoy_source_error_test.dart   |  5 +++
 16 files changed, 239 insertions(+), 12 deletions(-)

$ git diff --check
(aucune sortie ; code 0)
```

Le stat Git ci-dessus ne compte que les fichiers suivis. Les nouveaux fichiers
hydrographiques et les données restent non suivis, listés dans le status. Un
contrôle whitespace supplémentaire a vérifié les 23 nouveaux fichiers sans erreur.

**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.**
