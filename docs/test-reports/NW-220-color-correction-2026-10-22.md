# NW-220 — Mer, terres et marques : diagnostic et correction du 22 octobre 2026

## 1. Périmètre et état initial

- Dépôt et worktree : `/home/palms/NoWave`.
- Branche vérifiée avant modification : `feature/NW-220-satellite-bathymetry-colors`.
- HEAD initial : `d838461`. Worktree initial propre, aucun fichier suivi modifié.
- Téléphone reconnu par `adb devices` et `flutter devices` : LGN LX1,
  Android 15 / API 35, connexion Wi-Fi ADB `10.6.2.48:42267`.
- Aucune opération sur une autre branche ou un autre worktree. Aucun commit,
  push, PR, merge, changement Linear ou déploiement.

Les preuves locales sont dans `test-results/color-correction/` (ignoré par Git).
Les captures sont de vraies captures ADB de `lib/main.dart` ; les commandes VM
déplacent uniquement la caméra. Aucun faux profil, objet maritime ajouté ou GPS
simulé. Le fichier privé `mobile/.env.json` est réutilisé sans changement.

## 2. Deux passes d'analyse avant correction

### Passe 1 : code et producteurs de données

Lecture du style `GlobeStyle`, de `MarinePalette`, `MarineMapController`,
`GlobePresentation`, des contrôleurs de pitch et de rotation, des couches
maritimes, de `MarineViewport`, des routes et fournisseurs backend, des tests
et des rapports NW-220 précédents.

| Élément | Architecture constatée au HEAD initial |
| --- | --- |
| Fond | Import natif `basemap` : Mapbox Standard, thème `faded`, lumière `day` |
| Terres | Couleurs configurées dans Standard ; classes Terrain v2 `wood`, `scrub`, `grass`, `crop`, `snow` dans `nowave-landcover`, slot BOTTOM |
| Relief | Terrain v2 `hillshade`, `shadow` et `highlight`, opacité .22 jusqu'à Z12, fondu à 0 à Z16 |
| Eau de repli | `nowave-earth-ocean`, Streets v8 `water`, BOTTOM, `#002D51`, opaque, émission 1 |
| Bathymétrie | PNG backend, raster MIDDLE unique, Z5+, opacité 1, saturation et contraste additionnels 0, source Z14 puis overzoom |
| Bassins portuaires | BOTTOM, bleu clair à .18 ; sous le raster MIDDLE |
| Marques | Sources GeoJSON publiques `marine-features/seamarks/...geojson`, couches TOP, PNG maritimes distincts |
| Profondeurs | GeoJSON : contours sur grille Z12 fixe et sondes ; préparation Z12, affichage Z13 |

Hypothèses examinées indépendamment : mauvaise palette, interpolation source,
alpha/raster, eau Standard, bassins, ordre des couches et zoom ; pour les marques,
absence de données, route manquante, échec fournisseur, parsing, images, filtres,
placement et collisions. Pour les terres, aucune correction supplémentaire de
saturation Z4–Z6 n'existait.

### Passe 2 : observations externes et état natif

Les conclusions du code ont été confrontées aux réponses de production, à leurs
pixels, au style Standard effectivement téléchargé et au style chargé sur le
téléphone. L'inspection native confirme les expressions, les sources, les slots
et l'enregistrement d'images maritimes. La simple présence de fichiers PNG dans
le dépôt n'a pas été utilisée comme preuve d'affichage.

Le JSON Standard téléchargé confirme les options de couleurs utilisées, dont
`colorBuildings`. Les couches importées ont leurs propres dérivations de couleurs
et leur éclairage ; elles ne sont pas remplacées par un voile global.

Références techniques : [Standard et options](https://docs.mapbox.com/map-styles/reference/standard/),
[imports et configuration](https://docs.mapbox.com/style-spec/reference/imports/),
[expressions](https://docs.mapbox.com/style-spec/reference/expressions/).

## 3. Mer : cause démontrée et portée de la correction

Les tuiles de production portent déjà la couleur claire **dans les pixels PNG**.
Il ne s'agit donc pas seulement d'un éclaircissement produit par une couche
cliente. Les mêmes cellules XYZ, demandées au backend local du HEAD initial,
produisent la palette sombre demandée.

| Cellule de Marseille | Production | Backend local du dépôt |
| --- | --- | --- |
| Z9, 263/187 | 200 ; couleur dominante opaque `(185,229,247)` / `#B9E5F7` | 200 ; dominante `(2,77,110)` / `#024D6E` |
| Z14, 8435/6001 | 200 ; dominante `(211,240,251)` / `#D3F0FB` | 200 ; couleurs côtières autour de `(14,105,133)` / `#0E6985` |

Preuves : `production-bathymetry-{9,14}.png`, `local-bathymetry-{9,14}.png`,
leurs métadonnées réseau et `production-pixels.json` / `local-pixels.json`.
Les images conservent des pixels transparents et opaques ; le raster client
conserve une opacité de 1. Les bassins BOTTOM ne masquent pas ce raster MIDDLE.

Le code local possède déjà la rampe `#61AAA4`, `#0E6985`, `#014A6B`, `#00325A`,
`#002D51`, `#001731`, du peu profond au profond. Son inversion de la légende RGB
EMODnet, la LUT, les masques, le lissage prémultiplié et le cache restent
inchangés. La source visuelle conserve l'ordre bathymétrique de la rampe
EMODnet existante ; elle ne fournit pas ici un nouveau jeu de mètres bruts.
Aucun seuil métrique ni profondeur depuis la distance au rivage n'est inventé.

**Dépendance de production :** les résultats servis par le domaine distant ne
correspondent pas au producteur présent dans ce dépôt. La version exacte déployée
n'est pas connue : aucune lecture VPS ni inspection de ses conteneurs n'a été
faite. Changer `v=marine-palette-3` ne met pas le code serveur à jour. Aucun filtre
client destiné à compenser cette ancienne palette n'a été ajouté. Le rendu
sombre est testé avec un backend local explicite ; il n'est pas déclaré corrigé
sur le domaine de production.

## 4. Terres : implémentation ciblée

`LandColors` produit des expressions natives `interpolate(linear, zoom)` entre
Z4 et Z6. Les couleurs hexadécimales sRGB existantes sont converties en HSL ; la
saturation de l'extrémité corrigée vaut `S × .75`, à teinte et luminosité HSL
constantes. L'interpolation sRGB entre ces deux couleurs conserve ces composantes
et donne une réduction linéaire de saturation. Par exemple 60 % devient 45 %.
Les valeurs HSL de destination restent flottantes, sans arrondi intermédiaire
en RGB 8 bits.

| Zoom | Facteur de saturation | Réduction relative |
| --- | ---: | ---: |
| ≤ 4 | 1 | 0 % |
| 4.5 | .9375 | 6.25 % |
| 5 | .875 | 12.5 % |
| 5.5 | .8125 | 18.75 % |
| ≥ 6 | .75 | 25 % |

Couleurs concernées : les dix options Standard de surfaces terrestres (sol,
espaces verts, commercial, éducation, médical, industriel, bâtiments, autoroutes,
axes principaux, routes), les cinq classes personnalisées de couverture du sol
et les deux teintes du relief. Les branches transparentes des classes inconnues
restent transparentes.

Les mêmes expressions sont utilisées à la création du style et lors de sa
réinstallation. Aucun traitement Dart par événement de zoom, changement de
style par seuil, couche écran grise ou recréation de source n'est ajouté.
Les options d'eau, libellés et frontières ne sont pas transformées ; les
marques, dangers, signalements et contrôles Flutter sont hors de cette palette.
L'opacité et les effets de relief existants sont conservés.

Les tests Dart couvrent les fractions de zoom, le cas 60 → 45 %, les neutres,
les classes, l'alpha et le reload. Une seconde vérification Python, indépendante
de ces tests, évalue les expressions **relues depuis le style natif Android** :
119 contrôles analytiques sur 17 couleurs et sept zooms, à une tolérance de
`1e-12` pour les calculs flottants (`independent-review.json`). Les propriétés
des couches relues par l'API native normalisent les couleurs en RGBA 8 bits :
49 contrôles supplémentaires confrontent ce retour aux expressions analytiques,
avec un écart maximal observé de **0.5 niveau par canal sur 255**. L'égalité
flottante analytique n'est pas présentée comme une égalité parfaite après cette
quantification native.

La garantie numérique porte sur les couleurs de palette et les remplissages
personnalisés. Les pixels finaux sont aussi affectés par les dérivations internes
de Standard, son thème, l'éclairage, le relief, les mélanges et l'anticrénelage.
Elle ne constitue pas une mesure uniforme de 25 % sur chaque pixel d'une
photographie finale. Les couleurs dérivées en interne par Standard ne sont pas
réécrites individuellement.

## 5. Marques : localisation de la panne

Chaîne réelle : SHOM WFS / Open Waters / fournisseurs selon la couverture →
normalisation et fusion backend → GeoJSON NoWave → HTTP public sans Firebase →
parsing `MarineViewport` → cache borné et rétention → source `nowave-buoys` →
couches de bouées/aides fixes TOP → PNG correspondant à la catégorie.

| Requête distante observée | Résultat |
| --- | --- |
| `/api/v1/map/marine-sources` | 200 |
| `/api/v1/map/marine-features/seamarks/10/527/375.geojson` | 404 JSON `http_404` |
| `/api/v1/map/marine-features/seamarks/14/8435/6001.geojson` | 404 JSON `http_404` |
| `/api/v1/map/marine-features/seamarks/12/2108/1500.geojson` | 404 |
| `/api/v1/map/seamarks/14/8435/6001.pbf` | 200, 4 970 octets, 17 objets décodés |
| `/health` | 403 à la périphérie ; ne prouve pas une panne de toutes les routes |

L'application sur le téléphone constate les mêmes 404 pour les familles
GeoJSON : aucune marque n'arrive dans sa source, même si des images sont
enregistrées et si l'ancien PBF contient des marques. Les captures de référence
à Z12, Z14.5 et Z16 contiennent zéro objet GeoJSON et aucun symbole marin rendu.
La panne démontrée est donc **en amont du placement**, au contrat de routes du
serveur distant. Aucun changement de taille, de seuil ou d'opacité ne peut
remplacer ces réponses manquantes.

Le backend local du dépôt répond 200 / `X-NoWave-Marine-Status: ok` pour la cellule
de la marque témoin. L'ancienne route PBF n'a pas été substituée silencieusement
au GeoJSON : ses coordonnées quantifiées ne fournissent pas le contrat de
persistance NW-220.

### Marques réelles et diagnostic de collision

- SHOM `BALISAGE_BDD_WFS:bcnlat`, objet WFS `bcnlat.1247`.
- `inspireid=FR000002325000001`, `numald=1300255`, nom **Catalans**.
- Position : **5.3456225° E, 43.2914948° N**, entrée du Vieux-Port de Marseille.
- Identifiant NoWave : `shom:bcnlat:FR000002325000001`.
- Type : balise latérale tribord ; couleurs publiées vert/blanc horizontal,
  système IALA A, topmark et feu liés selon les données SHOM.
- Preuves : `shom-upstream-witness.json` (réponse WFS réelle mise en cache),
  `known-mark.json` (objet normalisé), `local-seamarks.json`.

Les catégories, images et règles IALA existantes ne sont pas modifiées.
L'inspection du style debug a été étendue pour relire le document Mapbox et les
dimensions des images réellement enregistrées. Elle ne crée aucun objet et ne
modifie pas les sources de données.

**Catalans reste masquée par les collisions normales**, y compris à Z16 alors
qu'elle est projetée au centre `(180, 402.5)` points. Une expérience de diagnostic
VM temporaire sur la seule couche `nowave-beacons-local` a passé
`icon-allow-overlap` et `icon-ignore-placement` à `true` : le même identifiant
SHOM est alors rendu. Un rechargement du style rétablit les propriétés normales
et le masquage. Preuves `collision-probe/{normal,overlap-enabled,normal-restored}.json/png`.
Cette expérience ne constitue pas un correctif de placement livré : aucune
règle de collision n'a été modifiée dans le code final. Le symbole vert/blanc
est enregistré et opérationnel ; l'expérience distingue son masquage d'un asset
manquant ou d'une erreur de parsing.

Le témoin utilisé pour les critères de persistance est donc la cardinale réelle
**Canoubier**, dont la couche prioritaire permet déjà le recouvrement selon les
règles existantes :

- SHOM WFS `bcncar.339`, `inspireid=FR000002335300001`.
- NoWave `shom:bcncar:FR000002335300001`.
- **5.3390001° E, 43.2842611° N** ; cardinale est, bandes jaune/noir/jaune,
  support de type tour, système IALA A.
- Données sources : `canoubier-shom-upstream.json` et `canoubier-normalized.json`.
- Réponses réelles transmises par le backend local, sans objet ajouté pour les
  captures.

| Zoom | Opacité native | Canoubier dans les résultats rendus |
| --- | ---: | --- |
| 9 | 0 | Non |
| 10 | 0 | Non |
| 10.5 | .25 | Oui |
| 11 | .50 | Oui |
| 11.5 | .75 | Oui |
| 12 | 1 | Oui |
| 13 | 1 | Oui |
| 14.5 | 1 | Oui, capture inspectée |
| 16 | 1 | Oui, capture inspectée |

Les huit couches de marques relues dans Android portent exactement l'expression
native Z10 → Z12 attendue et `minzoom=10`. Les 72 vérifications correspondantes
sont dans `native-opacity-verification.json`. Les 43 PNG et l'alias neutre
représentent **44 identifiants d'images**, tous présents et de dimensions 72×72
dans l'inspection native. Aucune catégorie prise en charge n'est fusionnée en
une icône générique ; les replis neutres pour qualifications insuffisantes
restent ceux du code initial.

## 6. Validations logicielles

### Passe 1

Commandes depuis `mobile/` :

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub test/core/map/land_colors_test.dart test/core/map/globe_style_test.dart test/core/map/marine/marine_map_controller_test.dart
```

Résultats : analyse sans anomalie ; **717 tests Flutter réussis** ; les trois
fichiers ciblés totalisent **13 tests réussis**.

Depuis la racine :

```sh
.venv/bin/python -m pytest backend/tests/unit/test_emodnet_bathymetry.py backend/tests/unit/test_marine_viewport.py backend/tests/unit/test_seamark_coast_audit.py backend/tests/api/test_marine_tiles.py -q
```

**63 réussites**, un avertissement de dépréciation Starlette/httpx. Le backend
n'est pas modifié. Les dépendances manquantes de l'environnement local ont été
installées depuis le verrou existant `backend/requirements-test.txt` ; aucun
fichier de dépendances du projet n'a changé.

### Passe 2

- Relecture du diff, du document Standard réel, des expressions relues dans
  Android et des chemins d'installation/reload ; aucun changement de zoom,
  source marine, parsing, géométrie, classification, collision ou annulation.
- `flutter analyze --no-pub` : aucune anomalie après correction d'un lint sur
  un littéral transparent du nouveau test.
- `dart format --output=none --set-exit-if-changed lib/core/map lib/features/map/data/marine_debug.dart test/core/map` : 20 fichiers, aucun changement.
- `flutter test --no-pub --reporter expanded test/core/map test/features/map/data/buoy_layer_test.dart test/features/map/data/fixed_aid_layer_test.dart test/features/map/data/marine_icon_image_test.dart test/features/map/data/marine_viewport_test.dart test/features/map/data/hydrography_layer_test.dart` : **67 réussites**.
- `.venv/bin/python -m pytest backend/tests/unit/test_emodnet_bathymetry.py backend/tests/unit/test_marine_viewport.py -q` : **26 réussites**.
- Vérification indépendante `independent-review.json` : 119 évaluations
  analytiques, 49 comparaisons avec le retour RGBA natif à ≤ .5/255 par canal ;
  **13 fichiers protégés
  identiques octet par octet au HEAD initial**, dont les zooms, viewport/cache,
  couches de marques, hydrographie, rotation, pitch, étoiles, écran carte,
  Nginx et producteur bathymétrique.

Les premiers essais des nouveaux tests ont révélé une quantification 8 bits de
leur évaluateur et des assertions encore adaptées aux constantes précédentes.
L'évaluateur utilise maintenant des canaux flottants ; les attentes anciennes
sont mises à jour vers les expressions correspondantes. Aucune assertion de
zoom, cache, erreur ou persistance n'a été retirée. Le test de formatage a été
suivi d'un formatage effectif puis d'une nouvelle vérification réussie.

Journaux : `analyze-{1,2}.log`, `focused-1.log`, `flutter-tests-{1,2}.log`,
`backend-targeted-{1,2}.log`, `format-2.log`.

## 7. Recette Android et captures

Le lancement de référence utilise le fichier d'environnement existant, avec
`API_BASE_URL=https://api.no-wave.fr/`. Pour la recette locale, seule la base
marine est explicitement surchargée ; les comptes et signalements conservent
leur backend distant et leurs tokens ne sont pas envoyés au serveur marin.

```sh
MARINE_CACHE_DIR=/home/palms/NoWave/test-results/color-correction/marine-cache .venv/bin/python -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8006
adb reverse tcp:8006 tcp:8006
# Depuis mobile/
flutter run -d 10.6.2.48:42267 --debug --no-pub --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8006/ --host-vmservice-port=8181 --disable-dds
```

Le build et l'installation réussissent. L'outil `aapt` du SDK hôte ne s'exécute
pas correctement sur cet hôte ARM ; Flutter utilise son repli vers le manifeste
source. Cet avertissement et l'avertissement KGP existant sont conservés dans
les journaux, sans présenter le build comme exempt d'avertissements. Un premier
chargement de profil a échoué temporairement ; le bouton normal Réessayer a
permis l'accès à la carte, sans contourner l'authentification.

Le document retourné par `getStyleJSON` peut conserver le style chargé
initialement. Les preuves finales utilisent aussi `getStyleLayers`,
`getStyleLayerProperties`, `styleSourceExists`, `getStyleSourceProperties` et
`getStyleImage`. Cette inspection confirme **32 couches NoWave** et la présence
des six sources bathymétrie/ports/marques/contours/sondes/dangers. La présence
effective d'un objet dans la chaîne de rendu est établie par son identifiant
dans `queryRenderedFeatures`, et pas seulement par ces métadonnées de sources.

### Emplacements des captures

Chemins relatifs à `test-results/color-correction/`, avec une PNG et un JSON
de caméra/données/rendu par zoom :

| Série | Position et zooms |
| --- | --- |
| `before-production/` | Marseille, 5.352610 / 43.300566 ; Z4, 4.5, 5, 5.5, 6, 8, 9, 10, 10.5, 11, 11.5, 12, 13, 14.5, 16 ; ancien rendu et routes distantes |
| `after-production-land/` | Même centre ; Z4, 4.5, 5, 5.5, 6, 8 ; seule la correction terrestre change, mêmes services distants |
| `after-local-sea/` | Même centre et caméra verticale ; Z5, 8, 9, 10, 12, 14.5, 16 ; palette et routes du backend local |
| `after-local/` | Première série locale complète, avec relevés de préparation/affichage des profondeurs ; à Z5 et Z5.5 le pitch existant vaut 15.556° et 44.444°, ce ne sont pas des comparaisons de caméra identique |
| `canoubier-matrix/` | Centre exact Canoubier ; Z9, 10, 10.5, 11, 11.5, 12, 13, 14.5, 16 ; visibilité et fondu |
| `known-mark-matrix/`, `collision-probe/` | Centre exact Catalans ; investigation du masquage et expérience de collisions réversible |
| `regressions/` | Trois cycles, déplacements Marseille et retours Canoubier, reload, interruption/reconnexion marine |

`land-z6-comparison.png` juxtapose les vraies captures avant/après terrestres.
`canoubier-matrix/opacity-crops.png` est une planche de recadrages des captures,
sans modification des couleurs ou des symboles. Les PNG originales restent
disponibles dans les dossiers ci-dessus. Les heures de la barre Android sont
celles configurées sur le téléphone, sans conversion utilisée pour les preuves.
Les planches `sea-local-matrix.png` et `land-comparison-matrix.png` permettent
l'inspection de tous les zooms de mer et de la transition terrestre ; elles
conservent les couleurs des PNG originales.

La recette constate huit réponses 503 de ports au préchargement régional Z6,
distinctes du défaut 404 de production et des marques testées. Les états utiles
aux zooms supérieurs se stabilisent ensuite sans erreur marine courante. Les
erreurs de la première série et leurs compteurs sont conservés dans les JSON et
`local-backend.log` ; aucune réussite n'a été fabriquée à partir d'une réponse
vide en erreur.

### Cycles, cache et rechargement

Trois cycles réels : Canoubier Z10 → Z12 → Z16 → déplacement à
5.37° E / 43.31° N à Z14.5 → retour Canoubier Z14.5 → Z16. Le témoin n'est pas
attendu dans le cadrage du déplacement ; il est retrouvé à chaque retour.
Il est également rendu après reload, lors du retour dans la zone mise en cache
pendant la coupure marine et après reconnexion. Les erreurs socket provoquées
par cette coupure sont conservées, puis disparaissent après rétablissement.
Les 44 images sont à nouveau présentes après reload.

Le contrôle indépendant `device-review.json` relit **47 états** :

- **262 comparaisons de géométries**, sur neuf identités de contours, sans
  remplacement des coordonnées.
- Au plus 45 snapshots, 400 574 octets de cache encodé et 977 699 octets retenus ;
  sous les plafonds existants 64 / 12 MiB et 4 MiB. Jusqu'à 1 670 lectures cache
  cumulées dans la session de cycles.
- Préparation des courbes et sondes constatée à Z12, aucun objet de profondeur
  rendu à Z12 ; à Z13, résultats natifs de sondes, **deux résultats de courbes
  majeures et un libellé** dans `canoubier-matrix/z13.json`. Les comptes combinés
  des deux cadrages Z13 figurent dans `device-review.json`.
- Après un geste réel relâché à Z0.7, longitude +9.255516° entre les deux mesures
  de `regressions/rotation.json`, avec latitude, zoom, bearing et pitch constants.
  Les échanges VM prennent du temps : ce delta n'est pas présenté comme une
  mesure de vitesse sur exactement quatre secondes.

La revue des ressources n'identifie aucun nouveau contrôleur, timer ou cache
dans le chemin de rendu. Le diagnostic ajouté s'exécute sur demande dans le
service VM debug. Ce contrôle n'est pas un profilage mémoire prolongé ni un
benchmark FPS/release.

## 8. Non-régression et critères d'acceptation

| Règle NW-220 | Preuve et résultat |
| --- | --- |
| Raster dès Z5 | Captures `after-local-sea/z5.png`, minzoom 5 et opacité 1 dans le style natif |
| Préchargement Z12, affichage Z13 | Tests, données reçues et résultats rendus décrits ci-dessus |
| Conservation des courbes | 262 comparaisons, géométries identiques |
| Marques Z10–Z12 | Huit expressions natives vérifiées ; Canoubier absent Z9/Z10, présent à tous les autres zooms demandés |
| Cache et persistance | Budgets respectés, trois cycles, reload, coupure et retour testés |
| Catégories et symboles | Fichiers de classification, couches et assets inchangés ; 44 images enregistrées |
| Rotation | Contrôleur inchangé, tests et rotation Android réelle |
| Frontières, halo, étoiles | Propriétés et couches conservées, tests de style et fichiers protégés |
| Nuages et Lune | Absents du style et de ses sources ; assertions existantes conservées |

| Critère demandé | État final dans le périmètre testé |
| --- | --- |
| 1. Pas de blanchiment artificiel | Validé avec le backend local ; **non corrigé en production** |
| 2. Gradients bathymétriques conservés | Validé localement, photos et tests du producteur ; aucune profondeur inventée |
| 3. Désaturation 25 % à partir de Z6 | Validée mathématiquement sur les palettes et remplissages ; réserve explicitée sur les dérivations internes de Standard et la quantification des pixels |
| 4. Transition Z4–Z6 | Validée par tests, expressions natives et captures aux six zooms demandés |
| 5. Apparition des marques | Validée localement avec Canoubier ; **non corrigée en production** tant que les GeoJSON répondent 404 |
| 6. Témoin à Z14.5 et Z16 | Validé localement, images et identifiant rendus, trois cycles |
| 7. Isobathes et sondes | Validé dans le périmètre NW-220 décrit ci-dessus |
| 8. Aucun recul fonctionnel | Aucun recul observé dans les tests et essais effectués ; pas de garantie sur tous les fournisseurs et toutes les zones |
| 9. Deux vérifications | Deux passes d'analyse, deux validations logicielles, contrôles numériques indépendants et recette réelle |
| 10. Preuves réelles documentées | Captures, JSON, réponses réseau, style, images et journaux locaux conservés |

**La mission n'est pas déclarée intégralement validée pour la production.**
La désaturation est implémentée ; les deux anomalies marines sont expliquées et
le fonctionnement du code actuel est démontré avec son backend local. Leur
résolution sur `api.no-wave.fr` dépend d'une publication backend distincte, non
autorisée dans cette mission.

## 9. Limites et état laissé sur l'appareil

- Résolu dans le code livré : transformation des palettes terrestres, fondu
  Z4–Z6, application initiale et après reload, diagnostic natif des couches et
  images.
- Validé avec le serveur local existant : palette marine sombre, marques
  disponibles, témoin Canoubier et règles NW-220.
- Non résolu sur le serveur distant : anciens pixels bathymétriques et routes
  GeoJSON manquantes. Aucun déploiement ni contournement automatique vers
  l'ancien PBF ou vers localhost.
- Cas de visibilité conservé : Catalans est masquée par les collisions normales.
  La sonde temporaire de recouvrement a été entièrement révoquée par reload.
- Portée colorimétrique : réduction exacte des palettes en HSL sRGB, avec la
  quantification native et les effets internes de Standard détaillés en §4 ;
  aucune garantie d'un facteur identique sur chaque pixel composite final.
- Fournisseurs : huit échecs 503 de préchargement régional des ports à Z6 sont
  observés ; aucune modification de leurs règles ni masquage de ces erreurs.
- Pas de validation iOS, release, navigation maritime sur le terrain ou test
  de toutes les catégories dans toutes les couvertures géographiques.

La compilation finale réutilise `.env.json` et remet `MARINE_API_BASE_URL` à
vide : **configuration principale de production**, sans dépendance à un reverse
USB/Wi-Fi local. La série locale ne doit pas être confondue avec cette
configuration finale. Le lancement d'un binaire précompilé par Flutter a échoué
sur la lecture du manifeste à cause de l'outil `aapt` hôte ; l'installation
finale utilise ADB et le lancement Android normal.

```sh
# Depuis mobile/
flutter build apk --debug --no-pub --target-platform=android-arm64 --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=
# Depuis la racine
adb -s 10.6.2.48:42267 install -r mobile/build/app/outputs/flutter-apk/app-debug.apk
adb -s 10.6.2.48:42267 shell am start -n fr.blueway.app/.MainActivity
```

SHA-256 de l'APK finale :
`db705af0556384699116988aa208823403b0291ff1f7f533c4fa5ed8ca0d06c9`.
Journaux : `final-build.log`, `final-production-run.log`, `final-install.log`.

Installation ADB finale : **Success**. Le SHA-256 du `base.apk` effectivement
installé est identique à celui ci-dessus (`installed-apk-verification.json`).
Le lancement Android atteint la carte normale, avec les signalements du backend
principal (`final-production-screen.png`). Une dernière sonde de la route des
marques distante confirme encore **404** (`final-production-route.json`) :
l'installation finale ne corrige pas cette dépendance serveur. Le serveur local
de recette a été arrêté et sa redirection ADB `tcp:8006` retirée.

## 10. Git final

HEAD reste `d838461`, branche initiale conservée. Huit fichiers de cette mission :

| Fichier | Changement |
| --- | --- |
| `mobile/lib/core/map/land_colors.dart` | Nouveau calcul HSL et expressions de zoom |
| `mobile/lib/core/map/globe_style.dart` | Expressions sur les couvertures du sol et le relief |
| `mobile/lib/core/map/marine/marine_palette.dart` | Expressions sur les options de surfaces terrestres de Standard |
| `mobile/lib/features/map/data/marine_debug.dart` | Inspection debug des images, couches et sources natives |
| `mobile/test/core/map/land_colors_test.dart` | Nouveaux contrôles numériques et de préservation |
| `mobile/test/core/map/globe_style_test.dart` | Attentes des couleurs transformées, conservation des autres assertions |
| `mobile/test/core/map/marine/marine_map_controller_test.dart` | Attentes des expressions terrestres, autres contrats conservés |
| `docs/test-reports/NW-220-color-correction-2026-10-22.md` | Présent rapport |

Les scripts de preuve sont conservés dans le dossier ignoré
`test-results/color-correction/scripts/`. `git diff --check` et le formatage
final sont propres. Le worktree final contient ces modifications locales,
sans commit. Aucun fichier d'environnement privé, asset de référence, règle
NW-220, code backend, dépendance, configuration de production ou autre worktree
n'est modifié par ce correctif. Aucune publication n'a été effectuée.
