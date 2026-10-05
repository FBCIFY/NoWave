# Contrat de données NoWave — v1

Le style n'est pas un fournisseur de données. Données nautiques de démo : **100 % fictives**,
au point 0°/0°. Le DEM Mapzen/AWS est réel et externe ; la scène nautique est fictive, avec des géométries et profondeurs synthétiques. Rien n'est une
observation nautique, y compris les secteurs, mouillages et caractéristiques de feux.

## Archives vectorielles réelles

MVT dans MBTiles, table `tiles` au schéma MBTiles standard (lignes TMS).
Métadonnées `format=pbf` ou `mvt`, `json.vector_layers` contenant `id=nowave`.
Le serveur expose des URL XYZ et convertit les lignes. Tuiles gzip acceptées.
La couche source unique `nowave` contient les objets suivants. Tous les objets
sont en coordonnées géographiques avant encodage MVT (GeoJSON WGS84).

| `kind` | Géométrie | Propriétés utiles |
|---|---|---|
| land | Polygon/MultiPolygon | îlots et rochers émergés inclus même sans nom |
| coast | LineString/MultiLineString | côte réelle |
| contour | LineString/MultiLineString | `depth_m` positif en mètres |
| depth_area | Polygon/MultiPolygon | `depth_m` ; option si raster indisponible, teintes par polygone |
| vegetation, urban, foreshore | Polygon/MultiPolygon | seulement données identifiées |
| road | LineString | `coastal=true`, `class=motorway/trunk/primary` |
| basin | Polygon | bassin portuaire |
| breakwater, quay, pontoon, bridge | LineString | ponts uniquement sur zones navigables |
| channel, entrance | LineString | chenaux et passes, jamais libellés |
| port | Point | `icon=port-commercial/pleasure/marina/industrial/military`, `name`, `rank` |
| lighthouse, light | Point | `icon=lighthouse/light-red/green/yellow/white/black`, `name`, `characteristic`, `rank` |
| buoy, beacon | Point | `icon`, `name`, `characteristic`, `virtual=false`, `rank` |
| anchorage, ship_anchorage | Point | `identified=true`, `icon=anchor/anchor-ship`, `name` |
| mooring, wreck, danger_rock, landmark | Point | `icon=mooring/wreck/danger-rock/landmark/landmark-tower/landmark-monument/landmark-chimney/landmark-pylon`, `name` |
| shoal, reef | Polygon | `name` facultatif |
| restricted, military, reserve, windfarm | Polygon | zones permanentes identifiées, `name` pour réserve |
| light_sector | Polygon | `color` ; géométrie dérivée des angles et de la portée réels |
| country | Point | `name` ; label pays issu de `country_label` régional, source GeoJSON embarquée indépendante du MVT côtier |
| sea_name, gulf_name, roadstead_name, coastal_city, coastal_town, bay_name, cape_name, island_name, beach_name, cove_name, calanque_name | Point | `name`, noms géographiques seulement |

Les types inconnus sont ignorés. Les exclusions demandées (sondes, AIS virtuelles,
ZEE, eaux territoriales, zones temporaires, travaux, pêche, baignade, aquaculture,
câbles, pipelines, dragage, TSS, routes maritimes, rampes, frontières, bâtiments
secondaires, rail, aéroports, eau intérieure, tunnels, terminaux et sous-marin)
n'ont aucune couche de rendu. Ne pas les normaliser vers un type autorisé.
Les ports de pêche et ferrys doivent être intégrés à la catégorie de port pertinente.
Aucune règle de proximité au littoral n'est calculée par le style : le préparateur
certifie `coastal=true`, les villes côtières et les amers visibles depuis la mer.

### Bouées

Sprites disponibles : `lateral-port`, `lateral-starboard`, `cardinal-n/e/s/w`
(Ouest = `w`), `safe-water`, `special`, `isolated-danger`,
`preferred-channel-port`, `preferred-channel-starboard`, `buoy-sphere`,
`buoy-spar`, `beacon`. Les onze familles conventionnelles acceptent `~cone`,
`~can`, `~sphere`, `~spar`, `~pillar` (ex. `cardinal-e~pillar`).
Le suffixe `~topmark` ajoute exclusivement le topmark déclaré et validé
(ex. `lateral-port~pillar~topmark`). Les sprites sans ce suffixe n'en affichent aucun.
Les noms historiques sont conservés ; les sprites nus sont des symboles de
catégorie abstraits et ne sont pas utilisés comme forme physique de secours OSM.

La normalisation régionale requiert une forme prise en charge, des couleurs
explicites et, pour les bandes, le motif explicite approprié. Une forme absente
ou inconnue reste auditée. Une latérale bâbord conique ou tribord cylindrique,
une latérale sphérique, des couleurs/motifs contradictoires ou un système IALA B
explicite restent non rendus. Aucune correction silencieuse de forme n'est faite.
`seamark:topmark:shape` et `seamark:topmark:colour` doivent être tous deux présents
et cohérents pour afficher un topmark ; un topmark incomplet/contradictoire laisse
l'objet dans l'audit. Une balise ayant une forme non prise en charge (`pile`,
`tower`, etc.) n'est pas transformée en bouée.

| Famille IALA A | Couleurs explicites du corps | Motif | Topmark si déclaré (forme ; couleur) |
|---|---|---|---|
| latérale bâbord | `red` | uni | `cylinder` ; `red` |
| latérale tribord | `green` | uni | `cone, point up` ; `green` |
| chenal préféré à tribord | `red;green;red` | `horizontal` | `cylinder` ; `red` |
| chenal préféré à bâbord | `green;red;green` | `horizontal` | `cone, point up` ; `green` |
| cardinale N | `black;yellow` | `horizontal` | `2 cones up` ; `black` |
| cardinale E | `black;yellow;black` | `horizontal` | `2 cones base together` ; `black` |
| cardinale S | `yellow;black` | `horizontal` | `2 cones down` ; `black` |
| cardinale W | `yellow;black;yellow` | `horizontal` | `2 cones point together` ; `black` |
| eaux saines | `red;white` | `vertical` | `sphere` ; `red` |
| danger isolé | `black;red;black` | `horizontal` | `2 spheres` ; `black` |
| spéciale | `yellow` | uni | `x-shape` ; `yellow` |

Les catégories `preferred_channel_port` et `preferred_channel_starboard` sont
lues dans `seamark:buoy_lateral:category` ou `seamark:beacon_lateral:category`.
La couleur seule ne permet jamais de déduire un chenal préféré. Références :
[OSM Buoys](https://wiki.openstreetmap.org/wiki/Seamarks/Buoys),
[OSM Beacons](https://wiki.openstreetmap.org/wiki/Seamarks/Beacons).
**Une région IALA B nécessite une normalisation distincte.**
Aucune portée de bouée ni hauteur de feu n'est affichée.

## Bathymétrie continue réelle

`--bathymetry-tiles` : URL raster XYZ PNG, 256 px, champ de profondeur réel
précoloré avec les arrêts de `tools/build_style.py:COLORS`. Interpolation linéaire
entre les arrêts, plateau 0–2 m, saturation à partir de 1000 m. Ne pas traiter
NoData comme une profondeur nulle. Masquer les terres et prévoir la couverture
utile à tous les zooms. Les courbes doivent provenir du même modèle, avec unités,
référentiel vertical, résolution, date, couverture et licence documentés.
`depth_area` est un fallback discret, pas un substitut exact au raster continu.

`--relief-tiles` optionnel : raster DEM Terrarium **masqué aux terres**. Hillshade
faible (exagération 0 à z7, 0,15 à z10, 0,20 à z14, 0,22 à z18).
`--relief-attribution` est requis avec une source personnalisée. Ne pas envoyer un DEM marin non masqué.

Le DEM Mapzen/AWS est chargé depuis Internet dans le POC. Le pilote Cassis
prépare explicitement ses sources OSM/SHOM avec un script séparé ; le serveur
ne les télécharge pas à l'exécution. Pour d'autres jeux de données, résolution,
couverture, licences et exactitude doivent être qualifiées auprès des producteurs.
Une source réelle manquante reste absente.

## Secteurs

L'adaptateur produit le polygone depuis une position vérifiée, les relèvements
vrais de début/fin et la portée maximale connue (milles nautiques × 1852 m),
en respectant le passage 360°/0° et la convention de relèvement de la source.
Sans ces valeurs, ne pas fabriquer de secteur. Les attributs lumineux sont
transmis dans `characteristic` sans ajouter la hauteur.

## Exemple de branchement

```bash
python3 cartography/server.py --host 0.0.0.0 \
  --mbtiles /chemin/nowave-reel.mbtiles \
  --bathymetry-tiles 'http://192.168.1.10:8080/bathy/{z}/{x}/{y}.png' \
  --relief-tiles 'http://192.168.1.10:8080/dem/{z}/{x}/{y}.png' \
  --relief-attribution 'Producteur et licence du DEM Terrarium fourni' \
  --attribution 'Producteurs, licences et dates des données fournies' \
  --center 5.37 43.29
```

Le mode MBTiles supprime toutes les sources de démonstration et refuse l'accès
aux données fictives. L'app affiche « Données fournies » ; cela ne certifie
pas la précision du fichier. Le backend métier et ses tuiles de signalement
restent indépendants : le media type MVT contient « mapbox » par convention
ouverte, sans dépendance au service Mapbox.

## Pilote Cassis réel

`CASSIS_REAL` utilise le même contrat de couches avec des sources locales
MVT/XYZ découpées à Cassis, avec un masque marin GeoJSON. Voir [CASSIS_REAL.md](CASSIS_REAL.md).
Chaque objet OSM conserve ses tags et son identifiant. La grille de profondeurs
SHOM distingue les sondes interpolées à 10 m, le MNT HOMONIM à 0,001° et NoData ;
aucune source DEMO n’intervient dans ce mode. `marina_extent` conserve la géométrie
OSM de marina pour les contrôles de couverture et n’est pas une couche visuelle
de profondeur. Le masque marin est vectoriel. Les sources tuilées réutilisent les mêmes
règles visuelles que les sorties intermédiaires GeoJSON/raster.
**Ne pas utiliser NoWave pour la navigation officielle.**

## Préparation régionale — précisions opérationnelles

`REGION_REAL` utilise le même moteur `build_real_area(profile)` que Cassis.
Le profil fournit les URLs vectorielles/raster, les zooms effectifs, la caméra,
le masque marin et les crédits ; tous les objets de la source MVT `features`
portent `source-layer=nowave`. Les données locales et leurs preuves sont décrites
dans `data/<region>/manifest.json`. Voir [FRANCE_MED_REAL.md](FRANCE_MED_REAL.md).

Mappings OSM régionaux explicites actuellement implémentés :

| Tags source | Objets NoWave |
|---|---|
| `natural=coastline` | `coast` depuis la ligne réelle uniquement |
| Polygones OSM de côte assemblés, déclarés | `land`, masque `water` |
| `leisure=marina` ; `seamark:type=harbour` avec catégorie reconnue | `port`, `marina_extent` pour polygone |
| `man_made=pier/quay/breakwater/groyne` | `pontoon/quay/breakwater` ; contour réel si polygonal |
| `seamark:type=light_major/light_minor`, `man_made=lighthouse` | phare/feu, couleur explicite requise pour un feu mineur |
| `buoy_*` / `beacon_*` : latérale, cardinale, eaux saines, spéciale, danger isolé | type et sprite précis ; latérales uniquement avec catégorie et couleur IALA A explicites |
| `landuse=forest/grass`, `natural=wood/scrub` | `vegetation`, intersectée avec la terre |
| `landuse=residential/commercial/industrial/retail` | `urban`, intersectée avec la terre |
| `waterway=dock` polygonal | `basin` |
| `highway=motorway/trunk/primary` dans la bande côtière | `road`, `coastal=true` |
| `place=city/town/island/islet`, `natural=bay/cape/beach` nommés | noms géographiques correspondants |
| `seamark:type=mooring/wreck/rock/anchorage` | `mooring/wreck/danger_rock/anchorage` identifié |

Les autres catégories du contrat restent acceptées par le moteur de style,
mais ne sont pas déduites automatiquement de tags insuffisants. En particulier,
les secteurs lumineux, ponts sur zones navigables, limites permanentes,
chenaux et amers qualifiés demandent des attributs supplémentaires et une
normalisation validée ; l’adaptateur ne les invente pas. Les objets nautiques
non normalisés figurent dans `osm-not-rendered.geojson`. Aucun objet inconnu
n’est promu dans une catégorie de secours.

Les IDs OSM, tags, versions, timestamps disponibles, empreinte de l’extrait,
source et licence sont conservés. Déduplication par `(osm_id, kind)` ; les
callbacks way/area ne doublent pas les polygones. Les géométries de relations
multipolygonales sont assemblées avec leurs anneaux intérieurs.

Bathymétrie régionale : catalogue schema 1, référentiel vertical commun,
produits avec raster monobande, signe `up/down`, résolution en mètres,
identifiant, date, source, licence, SHA256, métadonnées originales et polygone
de validité WGS84. `exclude` permet une exclusion qualifiée, dont les ports
non fiables à la résolution du produit. Aucun mélange vertical automatique.
La meilleure résolution valide gagne, puis priorité explicite à résolution
égale. Les conversions et déclarations restent auditables dans le manifest.

Les blocs du cache contiennent profondeur et identifiant de source par cellule.
NaN et source 0 signifient inconnu, jamais profondeur 0. Les courbes, avec
`product_id`, `resolution_m`, `grid_resolution_m`, `vertical_reference`, licence,
date et checksum, sont extraites du même champ que le raster. Elles ne
traversent pas les frontières de produits ni les trous de profondeur.

Les PNG gardent la palette validée, l’alpha prémultiplié pour les couleurs et
un masque de support empêchant l’interpolation d’étendre la zone connue.
Le zoom d’affichage ne certifie pas la résolution ou l’exactitude de la source.
Le relief terrestre est protégé par un masque marin global dérivé des terres
réelles, indépendant des limites des blocs. La bbox n’est jamais une côte.

**NoWave n’est pas une carte officielle de navigation.**

### Hiérarchie des labels régionaux

`country_label: {"name": "FRANCE", "coordinates": [4.8, 44.1]}` dans
`regions/france_med.json` place le pays sur les terres continentales françaises,
sans réseau ni ajout de la Corse. Sa source GeoJSON embarquée reste disponible
sous le minzoom 6 des tuiles vectorielles. La couche `country` est visible de z0
à z6 inclus, avec `maxzoom=COUNTRY_CITY_SWITCH_ZOOM=6.01` (exclusif).
`coastal_city` a `minzoom=6.01` (inclusif) et `maxzoom=12` (exclusif).
L'epsilon 0.01 laisse donc le pays jusqu'à z6.009… ; il évite un trou à z6.
Les deux couches ont une opacité 1 dans leur plage, sans fondu retardant les villes.
`coastal_town` garde son minzoom 12 ; les autres noms géographiques sont inchangés.
