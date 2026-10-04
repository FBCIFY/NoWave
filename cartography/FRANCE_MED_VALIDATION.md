# France Méditerranée réelle — bilan du 4 octobre 2026

La carte a été générée, publiée atomiquement, servie et affichée dans le POC
Flutter Web/MapLibre. La bande géométrique est de **30 NM = 55 560 m**.
La bathymétrie est connue sur **96,247 %** des cellules marines à 100 m ;
le reste demeure NoData. Cette proportion décrit le support du modèle acquis,
pas la complétude ou la précision de levés hydrographiques.

Génération locale : `1a8135e5e375494b8a17b428f313e65d`. Branche `feat/NW-map-style`,
référence initiale `20d86ab`. **NoWave n’est pas une carte officielle de navigation.**

## 1. Existant conservé

Le pipeline régional, ses catalogues, la normalisation conservatrice OSM,
les blocs/VRT, la publication par `current`, le serveur, les deux profils
Tippecanoe et le style générique existaient déjà. Le verrouillage de Cassis
et les tests d’échec/bascule atomique étaient présents. Configuration,
palette, résultats historiques Cassis à 10 NM et interface Flutter inchangés.
La référence était de 33 tests Python, 5 profils MapLibre et 7 tests Flutter.

## 2. Ajouts et corrections

Acquisition réelle épinglée ; préparation des sources hors Git ; complément
réel des références du Golfe du Lion ; audit des relations non interprétées ;
filtrage natif des tags après indexation des positions/assemblage des aires ;
buffers géométriquement équivalents par lots ; prédicats préparés évitant les
découpes inutiles. Les références non taguées des géométries restent présentes.
Le PBF extrait avant/après filtrage natif est **identique par SHA256** et les
comptages d’inventaire restent identiques : 198 510 objets, 990 non interprétés.
Lecture GeoJSON en flux pour l’audit, bilan par cellule et contrôle navigateur
réel. HTTP local limité aux builds Debug Android/iOS ; production HTTPS.
Aucun code GPS, cache Flutter ou téléchargement hors ligne ajouté.

## 3. Sources réellement acquises

- [Geofabrik Languedoc-Roussillon](https://download.geofabrik.de/europe/france/languedoc-roussillon.html)
  et [PACA](https://download.geofabrik.de/europe/france/provence-alpes-cote-d-azur.html),
  snapshots `261003`, même horodatage `2026-10-03T20:20:50Z`.
- [Terres OSM assemblées](https://osmdata.openstreetmap.de/data/land-polygons.html),
  README producteur `2026-10-04T00:00:00Z`, morceaux fusionnés dans
  `[1.5,41.0,9.2,45.2]` pour contrôler le buffer avant découpe.
- [Relation OSM 9287303 complète](https://api.openstreetmap.org/api/0.6/relation/9287303/full),
  92 041 nœuds et 692 ways ; chaque timestamp est antérieur ou égal au snapshot.
  Ce complément répare un multipolygone traversant les extraits, sans Overpass.
- [SHOM HOMONIM Golfe du Lion–Côte d’Azur](https://diffusion.shom.fr/donnees/bathymerie/mnt-facade-gdl-ca-homonim.html),
  archive **PBMA ZNEG**, produit 2015, archive publiée en 2018. Acquisition 2026
  de l’archive officielle et du record de catalogue CSW. XML original, ASC et
  descriptif conservés ; les sources de levés/interpolations du producteur
  restent celles du modèle régional, sans prétendre acquérir tous les levés.
- `coast_scope` : sept départements OSM 06, 11, 13, 30, 34, 66, 83 du même
  snapshot. Sélection de la côte française continentale et des îlots, exclusion
  des côtes espagnole, italienne, monégasque et corse. **Aucune frontière maritime officielle.**

URLs exactes, tailles, dates et provenance dans
[france_med.acquisition.json](regions/france_med.acquisition.json).
Téléchargements bruts : **1 695 353 570 octets**, plafond explicite 2 GiB.
Sources locales : `$HOME/.local/share/nowave/sources` ; aucun gros asset dans Git.

## 4. Licences

OSM, terres et complément OSM : **ODbL-1.0**, attribution OpenStreetMap.
HOMONIM : **Licence Ouverte 1.0 / Etalab, octobre 2011**, confirmée dans le XML
original acquis ; attribution Shom/DOI conservée. Voir aussi
[licence des terres](https://osmdata.openstreetmap.de/info/license.html).
Le relief terrestre Mapzen/AWS et ses crédits existants sont conservés ; il
n’est jamais utilisé comme profondeur sous-marine.

## 5. Empreintes et tailles des sources

Les deux PBF ont d’abord été vérifiés avec le MD5 producteur. Les SHA256 locaux
épinglent tous les contenus effectivement acquis ; aucune empreinte officielle
SHOM non fournie n’est revendiquée.

| Fichier brut | Octets | SHA256 |
|---|---:|---|
| `languedoc-roussillon-261003.osm.pbf` | 269 846 613 | `7290ba30d3113e6bd5dac551d59ebd340a6b66dafe8eb9001fae83e31e9c8234` |
| `provence-alpes-cote-d-azur-261003.osm.pbf` | 390 024 451 | `a430f9c162c7a985d551d4dd83c8f49aece25ea5c2dd6bc20136f2b867ef1d43` |
| `land-polygons-split-4326-20261004.zip` | 927 872 798 | `337b9b81903812e6d0d085a8fd1e92127fe4cc7bb8142e4169c902794bcaf27c` |
| `MNT_FACADE_GDL-CA_HOMONIM_PBMA.7z` | 89 507 090 | `fb4706cd3bc696485dc9da331e22db7ed99b4eec05feb301dc1a3f1fb2466425` |
| `homonim-metadata-20261004.xml` | 50 695 | `a53db011df3a352f14ae9a760368fd14d4acf2b783e3124e26959b4f322d0b38` |
| `gulf-of-lion-relation-9287303-full-20261004.osm` | 18 051 923 | `2e212f90920570ab453e81d4f11cd33de6d3ba5ae6b2bb06776a6bea9624c4d9` |

Empreintes importantes des dérivés :

| Dérivé | SHA256 |
|---|---|
| PBF de rendu complet, 141 218 057 octets | `f6af0de8451e2138e82c7dfb77e63290604b02bac2f2e723a7f236fdf2668169` |
| PBF extrait, références complètes | `9a95b6946b71d7ecb78850256918977d626b2cc60a43a624bc51878389fc0c85` |
| ASC original SHOM | `88de989fe8192cbe5dad2a82845ddc6933ff0c92964d681947588b23d74f619d` |
| GeoTIFF SHOM | `590e80b1241c1b5705f156e9bd643687df41972a161f9c10eab5b4cd3761afe3` |
| Empreinte de cellules SHOM valides | `fc4525cac0343bc8aee898a85d7f978af874c60f2eabe31eede477e0d3447d71` |
| Features publiées / entrée du MBTiles | `c0a76e58f0a329175522e23b65ea2dada421a7dacf58610983ff9655130517da` |

Les catalogues locaux conservent aussi les empreintes XML, terres et scope.
Le manifest de génération contient `files_sha256` ; les PNG ont des SHA256
par tuile, le MBTiles conserve `nowave:input_sha256` et son profil réel.

## 6. Couverture OSM et emprise obtenues

Le PBF extrait contient **15 443 053 nœuds, 1 101 577 ways, 10 114 relations**.
`osmium check-refs -r` : **zéro référence manquante**, pour tous les types.
250 relations incomplètes sans mapping rendu ont été exclues récursivement,
avec IDs/tags/raison. Une relation interprétable incomplète bloque la préparation.
Les 990 autres entrées d’audit ont toutes la raison « Unsupported or insufficient
explicit tags » ; aucun type n’a été deviné et aucune erreur de géométrie n’a
été masquée dans cet inventaire. Total `osm-not-rendered.geojson` : **1 240**.

Littoral sélectionné mesuré : **1 579,451 km**, en Lambert-93.
Buffer marin non découpé : environ
`[3.03452537,41.93694681,8.21996914,43.98733031]`.
Surface hors bbox `[2.4,41.85,8.3,44.45]` : **0 km²**.
La bbox n’a pas été changée et ne génère aucune côte. Surface marine géométrique :
**32 606,080 km²**. Les terres sont soustraites ; bande terrestre utile 3 km.
Ces mesures ne certifient ni frontières ni complétude des objets OSM.

**32 243 features publiées**, dont :

| Type du contrat | Nombre |
|---|---:|
| `anchorage` | 2 |
| `basin` | 28 |
| `bay_name` | 362 |
| `beach_name` | 630 |
| `beacon` | 98 |
| `breakwater` | 600 |
| `buoy` | 138 |
| `cape_name` | 263 |
| `coast` | 1 162 |
| `coastal_city` | 4 |
| `coastal_town` | 35 |
| `contour` | 4 920 |
| `danger_rock` | 3 |
| `island_name` | 38 |
| `land` | 1 |
| `light` | 177 |
| `lighthouse` | 138 |
| `marina_extent` | 153 |
| `mooring` | 57 |
| `pontoon` | 2 881 |
| `port` | 212 |
| `quay` | 27 |
| `road` | 6 592 |
| `urban` | 5 669 |
| `vegetation` | 8 025 |
| `wreck` | 28 |

Les **2 185 objets ponctuels OSM** ont également été retrouvés par décodage
réel aux zooms **6 et 14**, dans 554 tuiles testées : **aucun manquant**.
Les couches utilisent `source-layer=nowave` ; simplification aux petits zooms
selon le profil régional, maxzoom réel 14. Cassis conserve sa recette z6–18.

## 7. Bathymétrie réellement obtenue

Produit `MNT_MED100m_GDL_CA_HOMONIM_WGS84_PBMA_ZNEG`, WGS84, **PBMA**, élévations `positive=up` converties en
profondeurs positives. Grille originale **0,001°**, environ 111 m nord-sud ;
5001 × 2701 cellules, bounds `[2.8995,41.6995,7.9005,44.4005]`.
ASC → GeoTIFF float32 sans rééchantillonnage, CRS confirmé par XML.
NoData original `-99999`, altitudes positives exclues du support bathymétrique.
Le modèle source contient 8 066 719 cellules valides non positives.

Grille de traitement : 100 m, 31 blocs 512 × 512, VRT sparse.
**3 138 245 / 3 260 613** centres de cellules marines possèdent une profondeur,
soit **96,247 %**, environ **31 382,45 km²**. Un seul produit/référentiel est
utilisé ; chaque cellule connue a l’ID source 1. Profondeurs retenues :
**0 à 2 687,94 m**. Les **22 cellules réellement à 0 m** restent valides ;
elles ne remplacent jamais NoData.

Recalcul séparé sans cache avec Python 3.13 : mêmes 31 blocs de profondeur/RGBA
**à l’octet près par leurs SHA256**, 3,44 s. Raster et courbes utilisent le même
champ. Cette résolution régionale ne constitue pas un levé portuaire fin.

## 8. Lacunes et NoData

**122 368 cellules**, soit **3,753 %** et environ **1 223,68 km²**, restent
inconnues et transparentes. **1 162,02 km²** se trouvent dans les bandes de
longitude **7,9–8,3°E** (94,96 % des lacunes), principalement au-delà de la borne
est SHOM 7,9005°E. Les **61,66 km²** restants sont des trous répartis le long
du littoral/du support original ; les écarts de millésime littoral et les cellules
source absentes/non bathymétriques restent exclus. Aucun remplissage artificiel.
La scène Web `[8.05,43.75]`, z11, montre la limite des données et la mer NoData.

L’audit JSON local détaille les trous par bandes de 0,1° ; les estimations de
surface sont celles des centres de cellules à 100 m, pas une mesure vectorielle
exacte des levés. Les PNG entièrement transparents sont omis.

Complément public proposé séparément :
[EMODnet DTM 2024](https://emodnet.ec.europa.eu/en/emodnet-bathymetry-dtm-2024-release),
annoncé à 1/16 minute d’arc et couvrant la Méditerranée. **Non acquis, non intégré**.
Avant intégration, qualifier les fichiers exacts, licence, provenance, zones
réellement mesurées/interpolées, référentiel vertical et compatibilité avec PBMA.
Une emprise de modèle plus vaste ne prouve pas des sondes partout.

## 9. Tailles et performances mesurées

| Sortie | Octets |
|---|---:|
| Génération préparée (6 fichiers) | 81 112 284 |
| MBTiles z6–14, 33 030 tuiles | 24 645 632 |
| 309 PNG seuls | 4 458 439 |
| Répertoire raster, checkpoints/métadonnées compris | 4 538 196 |
| Cache bathymétrique de la génération | 21 552 329 |
| APK Release ARM64, sans données régionales | 27 406 164 |

Maximum d’une tuile MVT compressée : **424 298 octets**, sous la limite 500 000.
Aucun profil Cassis sans limites appliqué au régional.

| Étape (`/usr/bin/time -v`) | Temps | Pic RSS (KiB) |
|---|---:|---:|
| Préparation des sources, téléchargements exclus | 40,92 s | 2 405 976 |
| Région, extraction/inventaire reconstruits, 31 blocs repris | 342,68 s | 3 142 948 |
| Champ SHOM recalculé sans cache | 3,44 s | 238 792 |
| MBTiles | 3,86 s | 701 900 |
| PNG | 5,70 s | 369 200 |
| Audit géométrie/cellules/empreintes | 74,55 s | 444 088 |

Six scènes Flutter Web : **18 976 695 octets** servis par NoWave,
48 réponses 200 et 20 réponses 204. Ce total exclut Flutter/CDN/relief externe.
Le `water.geojson` précis seul pèse **17 488 247 octets** et domine ce transfert :
compression HTTP par reverse proxy recommandée pour une exposition HTTPS.
Aucun cache Flutter ni pack hors ligne n’a été implémenté.

## 10. Tests exécutés

- `.venv/bin/python -m unittest discover -s cartography/tests -v` : **42 réussis**,
  y compris oracle Cassis inchangé, références PBF, priorités/NoData/référentiels,
  profils Tippecanoe réels, conservation des points et publication atomique.
- `npm test --prefix cartography` : **5 profils MapLibre v8 valides**.
  Style régional réellement généré également validé : **61 couches**.
- `flutter test --no-pub` : **8 réussis** ; `flutter analyze --no-pub` : **aucun problème**.
- `bash -n cartography/tools/build_vector_tiles.sh` et `git diff --check` : réussis.
- Serveur réel : health/style/manifest/water/MVT gzip/PNG **200**, PNG absent
  **204**, traversal brut/encodé, générations internes, DEMO et autre région **404**.
  CORS vérifié ; URLs publiques HTTPS du style régional vérifiées.
- Tous les 309 PNG possèdent au moins un pixel visible ; **203** comportent
  aussi des pixels transparents. Aucune tuile entièrement transparente écrite.
- Chromium/Playwright sur le vrai build Flutter Web utilisant `MapLibreJsSource.cdn()` :
  façade z7, Marseille, Sète, Port-Vendres, Nice z15,3 et NoData est z11.
  Pan/zoom, sprites, glyphes, MVT, raster et masque marin chargés. **Aucune erreur**
  JavaScript/MapLibre, aucun échec réseau local, aucune requête DEMO ou propriétaire.
  Six captures réellement inspectées dans `test-results/france-med-real/` (ignoré).

## 11. Android

Builds natifs Debug et Release réussis avec Flutter 3.47.6/Dart 3.13.5,
JDK 21 complet et SDK Android 36. Le Release ARM64 séparé pèse **27,4 Mo**.
Inspection APK : uniquement ARM64 pour ce package, aucun PBF/MBTiles/GeoTIFF/GeoJSON
régional. Manifest final : Internet autorisé, HTTP clair Debug seulement.
Le Release de contrôle conserve la signature Debug du POC, pas une signature store.
**Test physique non exécuté : `adb devices -l` ne retourne aucun appareil.**
Le rendu Web ne vaut pas validation native Android.

## 12. Audit iOS

Dart commun, chargement distant via `NOWAVE_STYLE_URL`, style v8/endpoints
communs, API MapLibre sans branche Android. Plugin `maplibre_gl` **0.27.1**,
MapLibre Native **6.28.0**, minimum plugin iOS 13 ; projet **iOS 15.0/ARM64**.
Intégration Swift Package Manager présente, plugin avec `Package.swift` ;
pas de Podfile dans ce projet SPM. Fonts/sprites sont distants, aucun jeu régional
lourd dans le bundle. `Info-Debug.plist` permet seulement le réseau local ;
Release/Profile conservent ATS sans `NSAllowsArbitraryLoads`. Tests de cohérence
des plists et de sélection des configurations. Simulateur sur le Mac du serveur :
127.0.0.1 ; iPhone : IP LAN accessible ou domaine HTTPS. Voir [map_poc](../map_poc/README.md).

## 13. Build iOS

**Build iOS non exécuté : nécessite macOS + Xcode.** Aucun simulateur ou iPhone
validé depuis WSL. La résolution SPM par Xcode, la signature et le rendu natif
restent à contrôler sur Mac avec les commandes ci-dessous.

## 14. Fichiers modifiés ou ajoutés

Sources/performance : `regions/france_med.acquisition.json`,
`tools/prepare_france_med_sources.py`, `requirements-region.txt`,
`tools/regional_osm.py`, `tools/coastal_geometry.py`, `tests/test_real_sources.py`.

Audit/publication/documentation : `tools/prepare_region.py`, `tools/pipeline_io.py`,
`tools/audit_region.py`, `tools/browser_region.cjs`, `FRANCE_MED_REAL.md`,
`FRANCE_MED_VALIDATION.md`, `README.md` (tous sous `cartography/`).

Mobile : `map_poc/README.md`, `map_poc/test/map_style_test.dart`,
`map_poc/android/app/src/main/AndroidManifest.xml`,
`map_poc/android/app/src/debug/AndroidManifest.xml`,
`map_poc/ios/Runner/Info.plist`, `map_poc/ios/Runner/Info-Debug.plist`,
`map_poc/ios/Runner.xcodeproj/project.pbxproj`, `cartography/tests/test_mobile_config.py`.

Les deux catalogues `*.local.json`, les données, tuiles, APK, logs et captures
restent ignorés/hors Git. Aucune modification des données Cassis ou de la palette.

## 15. Commits

Trois commits locaux logiques :

- `76ad67e` — `feat(map): pin and prepare real Mediterranean sources`.
- `78d4562` — `fix(map): restrict local HTTP to Android and iOS debug builds`.
- `feat(map): audit and document real Mediterranean generation` — inclut ce
  bilan ; son empreinte s’obtient avec `git log -1 --oneline` après publication
  du commit et figure dans le rapport de fin.

Aucun merge, rebase, force-push ni push GitHub effectué.

## 16. Limites restantes

La présence de données OSM ne certifie pas tous les objets nautiques. Les tags
insuffisants restent audités. HOMONIM 2015 est un modèle régional interpolé,
avec résolution insuffisante pour certifier les intérieurs portuaires ; les
lacunes et différences de littoral ne sont pas artificiellement comblées.
Le buffer Lambert-93 n’est ni une frontière réglementaire ni une distance
géodésique officielle. Les sources OSM/CSW/terres à URL mutable doivent être
archivées : un changement de SHA256 bloque la reproduction exacte.

Les premiers essais non préfiltrés ont subi des segfaults natifs sous WSL avec
Python 3.14.4 et 3.13.16 ; la cause native n’est pas isolée. La chaîne finale
avec filtrage natif a terminé, extraction/inventaire reconstruits, avec
**CPython 3.13.16, pyosmium 4.3.1, Rasterio 1.5.2/GDAL 3.12.2, Shapely 2.1.2/GEOS 3.13.1**.
Le filtrage conserve le PBF extrait à l’identique et réduit l’itération Python.
Les tentatives interrompues n’ont jamais basculé `current` ; leurs staging
orphelins ont été retirés après succès. Utiliser le runtime testé.

Les VRT dépendent des blocs du cache pour une nouvelle génération de tuiles.
Données préparées et tuiles ont des publications distinctes, avec contrôle de
signatures avant style. Le relief Mapzen/AWS demeure externe. Le serveur POC
ne termine pas TLS : reverse proxy/certificat nécessaires pour production.
Validations physiques Android, build/rendu iOS et signature store restent à faire.

## 17. Reproduction exacte

Depuis le dépôt ; `python3.13`, `osmium`, `tippecanoe`, npm et Flutter disponibles.
Si nécessaire : `uv python install 3.13.16`. Conserver les fichiers épinglés
externes pour les URLs mutables. Retirer `--download` si les sources sont déjà là.

```bash
cd /home/palms/NoWave
python3.13 -m venv .venv
.venv/bin/pip install -r cartography/requirements-region.txt
.venv/bin/python cartography/tools/prepare_france_med_sources.py \
  --source-root "$HOME/.local/share/nowave/sources" --download
.venv/bin/python cartography/tools/prepare_region.py \
  --region france_med \
  --sources cartography/regions/france_med.sources.local.json \
  --bathymetry-catalog cartography/regions/france_med.bathymetry.local.json \
  --cache "$HOME/.cache/nowave/france_med" \
  --resolution 100 --block-size 512 --offline
NOWAVE_GENERATION="$(readlink -f cartography/data/france_med/current)"
cartography/tools/build_vector_tiles.sh \
  "$NOWAVE_GENERATION/features.geojson" \
  cartography/tiles/vector/france_med.mbtiles nowave regional
.venv/bin/python cartography/tools/build_bathymetry_tiles.py \
  --field-manifest "$NOWAVE_GENERATION/bathymetry.json" \
  --bbox 2.4 41.85 8.3 44.45 --output cartography/tiles/bathymetry/france_med \
  --min-zoom 6 --max-zoom 11
python3 cartography/tools/build_style.py --region france_med \
  --output cartography/france-med-regional-style.json
.venv/bin/python cartography/tools/audit_region.py --region france_med \
  --cache "$HOME/.cache/nowave/france_med" \
  --output "$HOME/.local/share/nowave/sources/regional-validation.json"
python3 cartography/server.py --region france_med --host 0.0.0.0 --port 8765
# Derrière le reverse proxy TLS : ajouter --public-url "https://<DOMAINE_NOWAVE>"
```

Validation :

```bash
.venv/bin/python -m unittest discover -s cartography/tests -v
npm ci --prefix cartography
npm test --prefix cartography
(cd map_poc && flutter pub get && flutter test --no-pub && flutter analyze --no-pub)
bash -n cartography/tools/build_vector_tiles.sh
git diff --check
git status -sb
# Avec serveur 8765 actif :
(cd map_poc && flutter build web --no-pub \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json)
# Autre terminal :
python3 -m http.server 8766 --bind 127.0.0.1 --directory map_poc/build/web
# Chromium Playwright installé (sinon : cd cartography && npx playwright install chromium) :
node cartography/tools/browser_region.cjs
```

Android, appareil connecté/autorisations USB ; serveur 8765 actif :

```bash
adb devices -l
adb -s "<ANDROID_DEVICE>" reverse tcp:8765 tcp:8765
(cd map_poc && flutter run -d "<ANDROID_DEVICE>" \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json)
```

Mac avec Xcode, depuis `map_poc/`, serveur NoWave sur le même Mac :

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
flutter run -d "<IOS_SIMULATOR>" \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
# Après configuration de la signature Apple :
flutter build ios --dart-define=NOWAVE_STYLE_URL="https://<DOMAINE_NOWAVE>/style.json"
# Pour iPhone en Debug sur LAN :
flutter run -d "<IPHONE_DEVICE>" \
  --dart-define=NOWAVE_STYLE_URL="http://<IP_DU_SERVEUR>:8765/style.json"
```

Build APK ARM64, détails JDK/signature et HTTPS dans
[map_poc/README.md](../map_poc/README.md). Aucun fichier cartographique régional
n’est inclus dans les applications ; futur cache/offline à faire avec APIs et
stockage applicatif multiplateformes.
