# France Méditerranée continentale — pipeline régional

**NoWave n’est pas une carte officielle de navigation.**

Les sources réelles acquises le 4 octobre 2026 sont figées dans
`regions/france_med.acquisition.json`. Les sources lourdes, catalogues locaux,
générations et tuiles restent hors Git. Les tests automatisés utilisent des
fixtures synthétiques, sans réseau ; elles ne sont jamais publiées comme SHOM.
Cassis reste l’oracle réel. Le bilan de la génération réelle figure dans
[FRANCE_MED_VALIDATION.md](FRANCE_MED_VALIDATION.md).

## Installation et commandes

Depuis `/home/palms/NoWave` :

```bash
python3.13 -m venv .venv
.venv/bin/pip install -r cartography/requirements-region.txt
```

Le runtime de validation est CPython 3.13.16. Les premiers traitements non
préfiltrés ont subi des segfaults natifs avec Python 3.14.4 et 3.13.16 sous WSL,
alors que les fixtures passaient ; leur cause native n’est pas établie.
Le traitement utilise désormais le filtre natif des tags utiles avant
l’itération Python. Si Python 3.13 est absent, l’installation utilisateur
`uv python install 3.13.16` évite de modifier le Python système.

`tippecanoe` et `osmium-tool` doivent être disponibles dans `PATH`. `osmium-tool`
sert à la préparation initiale des sources et à leur contrôle de références.
L’extracteur PBF utilise
`pyosmium==4.3.1` avec stockage des positions sur disque ; le binaire `osmium`
n’est pas nécessaire pour les préparations régionales ultérieures.
`pyproj==3.7.2` assure les transformations métriques.
Aucun GPU n’est utilisé.

Pour reproduire le jeu réel acquis, préparer ses sources avec le lock vérifié :

```bash
.venv/bin/python cartography/tools/prepare_france_med_sources.py \
  --source-root "$HOME/.local/share/nowave/sources" --download
```

Sans `--download`, cette commande vérifie et transforme uniquement les fichiers
déjà acquis. Budget total : 2 GiB. Les URLs `land-polygons` et API OSM/CSW sont
mutables : une évolution de contenu provoque un refus SHA256, jamais une mise
à jour silencieuse. Conserver les snapshots externes pour une reproduction
exacte. Les deux `*.local.json` sont produits automatiquement.

Pour un autre jeu de données, créer les déclarations à partir des modèles :

```bash
cp cartography/regions/france_med.sources.example.json cartography/regions/france_med.sources.local.json
cp cartography/regions/france_med.bathymetry.example.json cartography/regions/france_med.bathymetry.local.json
```

Pour chaque asset, préciser `path`, `sha256`, `source`, `license`, `date`.
Les chemins relatifs sont résolus depuis le catalogue JSON. Calculer les
empreintes après vérification des fichiers et des métadonnées du producteur :

```bash
sha256sum /data/nowave/sources/*
```

Dans le catalogue bathymétrique, copier `product_template` dans `products`,
renseigner les chemins/empreintes et vérifier le signe et le référentiel du
fichier réellement choisi. Ajouter autant de produits que nécessaire.
`products: []` provoque volontairement une erreur, sans profondeur de secours.

Préparation complète, locale et reprenable :

```bash
.venv/bin/python cartography/tools/prepare_region.py \
  --region france_med \
  --sources cartography/regions/france_med.sources.local.json \
  --bathymetry-catalog cartography/regions/france_med.bathymetry.local.json \
  --cache "$HOME/.cache/nowave/france_med" \
  --resolution 100 --block-size 512 --offline
```

Le profil de départ à 100 m convient à une première ingestion HOMONIM.
Pour exploiter des levés plus fins, choisir une maille adaptée (`--resolution 10`
par exemple), toujours par blocs. Une maille plus fine n’améliore pas une source
à 111 m ; chaque cellule conserve son produit source et sa résolution.

```bash
NOWAVE_GENERATION="$(readlink -f cartography/data/france_med/current)"
cartography/tools/build_vector_tiles.sh \
  "$NOWAVE_GENERATION/features.geojson" \
  cartography/tiles/vector/france_med.mbtiles nowave regional

.venv/bin/python cartography/tools/build_bathymetry_tiles.py \
  --field-manifest "$NOWAVE_GENERATION/bathymetry.json" \
  --bbox 2.40 41.85 8.30 44.45 \
  --output cartography/tiles/bathymetry/france_med \
  --min-zoom 6 --max-zoom 11

python3 cartography/tools/build_style.py --region france_med \
  --output cartography/france-med-regional-style.json

python3 cartography/server.py --region france_med
```

Le serveur construit également `/style.json` directement. Il vérifie le profil,
l’archive `nowave`, la génération du raster et l’empreinte du GeoJSON ayant servi
au MBTiles régional. Regénérer les tuiles après une nouvelle préparation.

Deux profils Tippecanoe sont explicites : `INPUT OUTPUT nowave cassis` et
`INPUT OUTPUT nowave regional`. Sans profil, seules les entrées/sorties historiques
Cassis sont reconnues. Cassis conserve exactement z6–18 et ses quatre options
sans simplification ni limites ; les variables de zoom ne changent pas cette recette.
Le profil régional utilise z6–14 par défaut, accepte `MIN_ZOOM`/`MAX_ZOOM`,
simplifie normalement sous le zoom maximal et conserve les points à tous les zooms
(`drop-rate=1`). La précision reste à 4096 unités par tuile ; les limites sont
500 000 octets compressés et 200 000 objets par tuile. Si elles ne peuvent être
respectées, la construction échoue et conserve l'archive précédente, sans retirer
silencieusement les objets nautiques. Les plages effectives sont lues dans le
MBTiles par le style ; MapLibre agrandit les dernières tuiles au-delà du maxzoom.
Le MBTiles contient `nowave:build_profile`, `nowave:input_sha256`,
`nowave:tippecanoe_version`, `nowave:minzoom`, `nowave:maxzoom`.
La construction publie le MBTiles par renommage atomique après succès.

Les tuiles bathymétriques sont XYZ, EPSG:3857, PNG RGBA 256 × 256 :
`/tiles/bathymetry/france_med/{z}/{x}/{y}.png`.
Le MVT est exposé sous `/tiles/vector/france_med/{z}/{x}/{y}.pbf`,
`source-layer=nowave` ; MBTiles stocke les lignes TMS.

Test sur HONOR connecté en USB et autorisé :

```bash
adb devices -l
# Si le HONOR est le seul appareil USB connecté :
adb -d reverse tcp:8765 tcp:8765
NOWAVE_HONOR_SERIAL="$(adb -d get-serialno)"
cd /home/palms/NoWave/map_poc
flutter run -d "$NOWAVE_HONOR_SERIAL" \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Laisser le serveur actif dans un autre terminal. Aucun AppBar, bandeau, légende
permanente ni GPS n’est ajouté. Aucun appareil HONOR n’était connecté lors de
cette implémentation ; la validation physique France Méditerranée reste à faire.

## Géométrie et emprise métier

Configuration : `regions/france_med.json`, bbox `[2.40,41.85,8.30,44.45]`,
centre `[5.35,43.15]`, zoom 7, Corse exclue. La couverture maritime cible
est de **30 NM, soit 55 560 m**, depuis le littoral réel sélectionné. La bbox
reste un espace de travail, pas une déclaration de côte, de frontière maritime
ou de couverture bathymétrique.

La diffusion prévue utilise le serveur cartographique NoWave comme source principale.
Le cache local Flutter puis le téléchargement hors ligne par zone seront ajoutés
ultérieurement. Ils ne sont pas encore implémentés dans ce pipeline.

Trois entrées géographiques sont nécessaires :

1. Un instantané OSM PBF couvrant la région, avec ses références complètes.
2. Des polygones terrestres OSM assemblés, découpés à cette région (pas un
   polygone administratif utilisé comme terre). La mer est le complément de
   ces terres dans la bbox ; ce masque couvre le relief sous-marin.
3. Un polygone de sélection documenté du littoral français continental,
   `coast_scope`, excluant les portions espagnoles et italiennes présentes dans
   la bbox. Il doit inclure les îlots voulus et la ligne de côte. Une limite
   administrative au trait de côte peut nécessiter une marge documentée pour
   absorber les différences de millésime. Cette sélection ne certifie aucune
   frontière maritime et n’engendre jamais une ligne de côte.

Le littoral provient **uniquement** des ways OSM `natural=coastline`, intersectés
avec `coast_scope`. On ne prend jamais la frontière d’un polygone découpé comme
côte. Son buffer marin vaut **30 × 1852 = 55 560 m**, calculé en **EPSG:2154
(RGF93 / Lambert-93)**, adapté à la France continentale, puis soustrait des
terres. Une bande terrestre de 3 km conserve les objets côtiers utiles.
Les opérations métriques arrondissent les coordonnées au centimètre pour
stabiliser les découpes ; les fragments sans surface sont supprimés. Ce choix
est une approximation métrique documentée, pas une limite réglementaire.

Le masque terre/mer est construit une fois pour toute la région, avant les
blocs. Les contours de blocs ne deviennent ni côtes ni limites de profondeur.
Les polygones source doivent être valides et en WGS84. Les fichiers géométriques
d’entrée sont plafonnés à 128 MiB : ne pas fournir le GeoJSON mondial.

## OSM : acquisition et normalisation

Source vérifiée le 4 octobre 2026 : [Geofabrik France](https://download.geofabrik.de/europe/france.html).
Les snapshots datés `261003` Languedoc-Roussillon (269 846 613 octets) et PACA
(390 024 451 octets) ont été acquis et vérifiés par MD5 producteur puis SHA256.
Ils partagent l’horodatage `2026-10-03T20:20:50Z`. Le préparateur de sources
les fusionne sans tronquer les ways. Le multipolygone du Golfe du Lion traverse
les extraits : ses références ont été acquises depuis l’API OSM officielle,
figées par SHA256 et contrôlées comme antérieures au même horodatage.
Les relations incomplètes sans mapping rendu sont exclues récursivement et
consignées dans l’audit ; une relation rendue incomplète bloque le traitement.
Le PBF final passe `osmium check-refs -r` avec zéro référence manquante.

`fetch_source.py` fournit une acquisition facultative, explicite, plafonnée et
reprenable. Lui donner une URL HTTPS obtenue du producteur, une taille connue
et un SHA256 vérifié ; une URL ou une empreinte manquante n’est jamais inventée :

```bash
.venv/bin/python cartography/tools/fetch_source.py \
  --url "$NOWAVE_SOURCE_URL" --sha256 "$NOWAVE_SOURCE_SHA256" \
  --size-bytes "$NOWAVE_SOURCE_BYTES" --max-bytes "$NOWAVE_DOWNLOAD_BUDGET" \
  --output /data/nowave/sources/france.osm.pbf
```

Les variables sont à renseigner après estimation ; le plafond par défaut est
512 MiB. Un `.part` reste hors des entrées publiées jusqu’à validation intégrale.
Si seul un autre checksum officiel est disponible, acquérir et vérifier ce
fichier par l’outil du producteur, puis consigner son SHA256 local.

Les [polygones terrestres OSM assemblés](https://osmdata.openstreetmap.de/data/land-polygons.html)
sont issus de `natural=coastline`, avec réparation topologique par le fournisseur.
La variante découpée comporte un recouvrement entre morceaux, fusionné par le
pipeline. Après acquisition contrôlée du Shapefile WGS84, un export régional
peut être préparé avec GDAL (outil optionnel pour cette conversion initiale) :

```bash
ogr2ogr -f GeoJSON /data/nowave/sources/land-france-med.geojson \
  /data/nowave/sources/land-polygons-split-4326/land_polygons.shp \
  -clipsrc 2.39 41.84 8.31 44.46 -t_srs EPSG:4326
```

La préparation réelle utilise pyshp et fusionne les morceaux dans une emprise
plus large `[1.5,41.0,9.2,45.2]`, pour auditer le buffer avant découpe.
Le README du fournisseur date les données terrestres du `2026-10-04T00:00:00Z`.
Le `coast_scope` est l’union des sept départements OSM 06, 11, 13, 30, 34, 66,
83 du même snapshot PBF. Les IDs, versions et tags sont conservés. Cette
sélection exclut les portions espagnoles, italiennes et monégasques ; elle
n’est ni émise comme côte ni présentée comme une frontière maritime officielle.

L’extracteur pyosmium fait des lectures séquentielles du PBF : géométries
intersectant la région, assemblage des multipolygones, puis récupération de leurs
références (ways, nodes, relations imbriquées jusqu’à dix niveaux).
Les positions et les identifiants sélectionnés utilisent le disque. Le PBF
extrait est conservé dans le cache avec checksum ; les caractéristiques utiles
sont ensuite normalisées dans SQLite, clé `(osm_id, kind)`, et exportées en flux.
Le filtre natif `KeyFilter` intervient après le stockage des positions et
l’assemblage des aires : les références non taguées restent disponibles. La
récupération des références conserve aussi les relations pouvant hériter des
tags de leurs ways extérieurs. Les tests vérifient ces cas. Les prédicats préparés
évitent les intersections coûteuses des objets entièrement hors de la zone
utile ou déjà intégralement à l’intérieur, sans simplifier leur géométrie.
Les représentations way/area d’un même objet ne créent pas de doublon.
Les polygones de relations conservent leurs trous. Les objets distincts portant
des IDs différents ne sont pas fusionnés sur une simple proximité.

Préservation : identifiant, tags, version, timestamp disponible, date et
empreinte du PBF, provenance, licence. Les types nautiques insuffisamment définis
sont consignés dans `osm-not-rendered.geojson`, sans type connu de substitution.
Voir DATA_CONTRACT.md pour la table des mappings actuellement implémentés.
Aucune requête Overpass régionale n’est effectuée.

## SHOM : produits, références et NoData

Source officielle vérifiée le 4 octobre 2026 :
[HOMONIM Golfe du Lion–Côte d’Azur](https://diffusion.shom.fr/donnees/bathymerie/mnt-facade-gdl-ca-homonim.html),
[spécification de contenu](https://services.data.shom.fr/static/specifications/Descriptif_Contenu_MNT_facade_2020.pdf).
HOMONIM est annoncé à **0,001° (~111 m)**, WGS84, références **NM ou PBMA**,
formats ASC/GLZ/BAG/GRD, Licence Ouverte/Open Data. Ces informations de catalogue
ne garantissent pas une profondeur valide dans chaque port ou chaque cellule.
La couverture effective est l’intersection de l’emprise déclarée, des cellules
valides du fichier, du masque marin et de la bande côtière.

Le jeu acquis utilise réellement l’archive officielle HOMONIM PBMA ZNEG,
son ASC, son XML original et son descriptif 2015. L’ASC a été converti sans
rééchantillonnage en GeoTIFF float32, avec EPSG:4326 confirmé par le XML.
Le NoData original `-99999` est conservé ; les altitudes positives sont exclues
de l’emprise bathymétrique. Le XML confirme la Licence Ouverte 1.0 (Etalab).
Le template reste destiné à déclarer d’autres produits effectivement acquis.
**S201300200 n’est jamais présenté comme une couverture régionale.**
Les dates de levés, résolutions et licences des compléments portuaires doivent
être reprises de leurs propres métadonnées. Il n’existe pas ici de découverte
automatique prétendant fournir tous les levés nécessaires.

Entrée par produit : raster monobande géoréférencé lisible par GDAL (GeoTIFF
recommandé), NoData explicite dans le fichier ou le catalogue, `positive=up`
pour des altitudes signées / `positive=down` pour des profondeurs, référence
verticale explicite, polygone WGS84 de validité et métadonnées originales.
Le signe `up` du modèle fourni doit être vérifié sur le fichier acquis ; un
fichier exprimé en profondeur positive utilise `down`.
Pour convertir un ASC officiel sans interpoler ni modifier son NoData :

```bash
gdal_translate -of GTiff -co TILED=YES -co COMPRESS=DEFLATE \
  /data/nowave/sources/homonim-pbma.asc /data/nowave/sources/homonim-pbma.tif
```

Ne définir `-a_srs EPSG:4326` que si la projection absente du fichier est confirmée
par ses métadonnées. Ne pas écrire un `-a_nodata` deviné. Conserver le fichier
original et documenter la transformation. Les XYZ ponctuels exigent en amont une
grille validée avec support mesuré et NoData ; le moteur régional ne transforme
pas un nuage ponctuel en surface extrapolée. La recette Cassis des sondes reste
dans son adaptateur historique avec ses contraintes de support mesuré.

Tous les produits doivent utiliser le même référentiel vertical. Un mélange
NM/PBMA/ZH est refusé, sans décalage arbitraire. Une conversion verticale justifiée
se fait en amont et doit conserver sa provenance dans le catalogue.
Les produits sont ordonnés par résolution croissante, puis priorité décroissante
à résolution égale, puis identifiant. La première cellule **valide** gagne ; une
cellule fine NoData n’efface pas une cellule grossière valide.

L’emprise de validité peut être affinée avec `exclude` (asset polygonal déclaré
comme `coverage`) pour retirer des zones où le produit grossier n’est pas fiable,
notamment les intérieurs portuaires. Cette qualification doit provenir du
producteur ou d’une revue explicite : la présence dans une bbox ne suffit pas.
Les mailles terrestres, négatives après conversion en profondeur, hors emprise
ou NoData restent inconnues. **Aucun remplissage par 0.** Une profondeur mesurée
égale à 0 reste une vraie valeur distincte de NoData.

## Blocs, cache et mémoire

La grille régulière est alignée sur Lambert-93, blocs de 512 × 512 par défaut,
configurables entre 16 et 2048. Seuls les blocs intersectant la bande utile sont
calculés. Les lecteurs WarpedVRT opèrent par fenêtre, sans charger les rasters
sources ni une grille de 10 m sur toute la bbox. Mémoire GDAL de reprojection
plafonnée à 64 MiB par lecteur et cache GDAL global à 64 MiB, tableaux de calcul proportionnels à un bloc ;
le nombre de lecteurs ouverts reste proportionnel au nombre de produits.
Les géométries côtières régionales et les références de relations OSM restent
en mémoire ; ce n’est pas une garantie de mémoire constante pour un PBF mondial.
Les buffers du littoral sont calculés par lots de lignes puis réunis, avec
le même rayon et sans simplification. Cela évite le graphe intermédiaire de
plus de 15 Go observé lors d’un buffer global du littoral réel.

Chaque génération est identifiée par le catalogue, les checksums, la couverture,
la maille, la taille des blocs et le code de mosaïque/palette. Les blocs sont des
GeoTIFF à deux bandes : profondeur (`NaN` = NoData), identifiant de produit
(0 = aucun). Les fichiers RGBA associés proviennent exactement de ce champ.
Les empreintes des deux fichiers sont contrôlées avant réutilisation ; une
écriture interrompue ou un bloc corrompu est recalculé. Les anciennes générations
restent dans le cache, permettant une purge manuelle après revue.

Les VRT assemblent virtuellement les blocs, sans raster continental monolithique.
Les courbes lisent un halo d’un échantillon depuis **ce même VRT**. Chaque cellule
de contour appartient à un seul bloc ; les contours ne traversent ni trou NoData
ni frontière entre produits. Des interruptions de courbes entre produits sont
volontaires, afin de ne pas suggérer une continuité bathymétrique non établie.
Les courbes ne sont pas interpolées séparément depuis les données brutes.

Le raster XYZ lit une tuile à la fois, uniquement dans les emprises des blocs
contenant des cellules valides. Les tuiles entièrement transparentes sont omises
(HTTP 204) ; les trous des autres tuiles gardent alpha=0. Couleurs linéaires selon la palette Cassis,
alpha prémultiplié pendant le rééchantillonnage, contrôle de validité au plus
proche et alpha nul sans profondeur. Le plus proche sur le champ conserve les
trous NoData ; le bilinéaire porte sur les couleurs d’affichage, pas sur la
création de profondeurs nouvelles. Des checkpoints permettent la reprise par
tuile ; les anciennes PNG hors plage sont retirées uniquement après un rebuild
réussi dans le dossier de sortie indiqué.

Le zoom raster est contrôlé par la résolution effective source/grille et la
latitude. z11 est une proposition initiale pour HOMONIM ; un zoom plus élevé
nécessite une source réellement plus fine. L’agrandissement MapLibre ne crée
aucune résolution supplémentaire. Le relief Mapzen/AWS conserve la source et
l’attribution Cassis ; sa disponibilité nécessite Internet au rendu, sauf
fourniture d’un DEM Terrarium auto-hébergé avec attribution.

Ne déplacer ni purger le cache avant d’avoir produit les PNG : les VRT référencent
les blocs du cache. Les GeoJSON, PNG, MBTiles et styles publiés sont autonomes ;
les manifests conservent les chemins et checksums permettant l’audit local.
Les données préparées sont publiées comme une génération entière :
`data/france_med/current -> generations/<generation_id>`. Le préparateur écrit
uniquement dans un staging unique, valide chaque fichier, calcule les SHA256,
écrit le manifest final, synchronise les fichiers/répertoires puis bascule le
symlink avec `os.replace`. Un échec avant la bascule conserve la génération
précédente. Le staging est nettoyé ; les anciennes générations publiées restent
lisibles et ne sont pas recopiées. Le manifest contient `generation_id` et
`files_sha256` (tous les autres fichiers de la génération).

Les URLs `/data/france_med/water.geojson` et `/data/france_med/manifest.json`
résolvent la génération courante côté serveur, une fois par requête. Les chemins
internes de staging/générations ne sont pas exposés. Les lecteurs de fichiers
locaux doivent utiliser `current` ou conserver le résultat de `readlink -f`,
comme dans les commandes ci-dessus. Une requête commencée sur A peut finir sur A
après la bascule ; une requête suivante lit B. Ce n'est pas une transaction entre
plusieurs requêtes HTTP indépendantes.

Cette atomicité couvre les GeoJSON, `bathymetry.json` et le manifest de préparation.
Les PNG et le MBTiles restent des étapes distinctes : régénérer les deux avant
la remise en service du style si les données changent. Le style refuse les
signatures incohérentes. La bascule simultanée de l'ensemble données + tuiles
n'est pas incluse dans cette publication des fichiers préparés.

## Vérifications et limites restantes

```bash
.venv/bin/python -m unittest discover -s cartography/tests -v
npm test --prefix cartography
(cd map_poc && flutter test --no-pub && flutter analyze --no-pub)
```

La suite standard ne nécessite Internet ni jeux régionaux externes. Elle vérifie
les configurations, le buffer métrique, la bbox Overpass Cassis, les empreintes
des données Cassis, le style exact, le PBF et les objets dédupliqués, les blocs,
la reprise, la corruption, les références verticales, NoData, raster RGBA,
les styles MapLibre, un vrai MBTiles Tippecanoe et le serveur HTTP.

Le MNT régional ne remplace pas des levés portuaires fins. Les cellules absentes,
les écarts de littoral entre millésimes et les zones hors support du produit
restent NoData. Aucun complément externe d’un autre référentiel n’est mélangé.
Les mesures de couverture, tailles, temps et contrôles HTTP figurent dans
[FRANCE_MED_VALIDATION.md](FRANCE_MED_VALIDATION.md). Les essais physiques
Android et iOS restent dépendants d’un appareil et, pour iOS, de macOS/Xcode.

## Régénération après modification des icônes OSM

Les sprites 1x/2x et le style seuls ne demandent aucune reconstruction SHOM.
Après un changement du mapping `icon`, régénérer les objets vectoriels et MBTiles
à partir des mêmes sources locales. Le mode `--osm-only` conserve le champ,
les contours, les signatures et les PNG SHOM existants. Il vérifie les empreintes
publiées et refuse des sources, une configuration de couverture ou une grille différentes ; la
publication par génération reste atomique. Les objets non concernés, les contours
et les masques de couverture sont conservés. Aucun téléchargement n'est effectué.

```bash
.venv/bin/python -c "import sys; sys.path.insert(0,'cartography/tools'); from generate_demo import sprites; sprites()"
.venv/bin/python cartography/tools/build_style.py

.venv/bin/python cartography/tools/prepare_region.py \
  --region france_med \
  --sources cartography/regions/france_med.sources.local.json \
  --cache "$HOME/.cache/nowave/france_med" \
  --resolution 100 --block-size 512 --offline --osm-only

NOWAVE_GENERATION="$(readlink -f cartography/data/france_med/current)"
cartography/tools/build_vector_tiles.sh \
  "$NOWAVE_GENERATION/features.geojson" \
  cartography/tiles/vector/france_med.mbtiles nowave regional

.venv/bin/python cartography/tools/build_style.py --region france_med \
  --output cartography/france-med-regional-style.json
```

Ne pas relancer `build_bathymetry_tiles.py` pour ce changement : la signature
bathymétrique est conservée. Arrêter le serveur pendant préparation + reconstruction
MBTiles, puis le relancer pour éviter une incohérence transitoire entre les étapes.
Le serveur vérifie toujours l'empreinte du GeoJSON vectoriel.

L'inventaire local acquis contient des formes `pillar`, mais aucune catégorie
`preferred_channel_port/starboard` ; leur support est vérifié par fixtures,
sans ajout d'objet réel. Les formes absentes/non supportées et les topmarks
incomplets restent dans `osm-not-rendered.geojson`. Les atlas contiennent
les noms historiques et les variantes avec topmark explicite.

Validation navigateur régionale (avec le serveur cartographique sur 8765 et
le client Flutter Web existant sur 8766) :

```bash
node cartography/tools/browser_region.cjs
```

Le test vérifie aussi les labels à z6, z6.01, z11.99 et z12.

Le mode complet a rencontré un segfault GEOS dans l'union des buffers côtiers
sur ce jeu réel. Le mode `--osm-only` évite ce calcul : il réutilise la couverture
marine validée et conserve le seuil terrestre de 3 km depuis la côte réelle.
Il ne corrige pas le problème natif d'une reconstruction complète de couverture.
