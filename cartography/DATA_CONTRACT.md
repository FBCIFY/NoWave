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
(Ouest = `w`), `safe-water`, `special`, `isolated-danger`, `buoy-sphere`,
`buoy-spar`, `beacon`. Les neuf premières familles acceptent `~cone`, `~can`,
`~sphere`, `~spar`, par exemple `cardinal-e~spar`. Préserver la forme réelle
et le type lors de la normalisation ; ne pas déduire une forme d'une donnée absente.
Les cardinales utilisent deux cônes orientés et bandes noir/jaune ; les marques
spéciales une croix ; eaux saines sphère rouge et bandes verticales rouge/blanc ;
danger isolé deux sphères noires et bandes noir/rouge. Les variantes latérales
rouge/vert correspondent à la région IALA A. **Une région IALA B nécessite une
normalisation adaptée aux couleurs réelles**, ne pas supposer les couleurs.
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
GeoJSON/image découpées à Cassis. Voir [CASSIS_REAL.md](CASSIS_REAL.md).
Chaque objet OSM conserve ses tags et son identifiant. La grille de profondeurs
SHOM distingue les sondes interpolées à 10 m, le MNT HOMONIM à 0,001° et NoData ;
aucune source DEMO n’intervient dans ce mode. `marina_extent` conserve la géométrie
OSM de marina pour les contrôles de couverture et n’est pas une couche visuelle
de profondeur. Le masque marin est vectoriel. Les futures sources tuilées
pourront remplacer ces petites sources locales sans changer les règles visuelles.
**Ne pas utiliser NoWave pour la navigation officielle.**
