# Cassis — premier port pilote réel

Scénario supplémentaire, isolé de la démo graphique. Les six captures de
`previews/final-style/` et les sources DEMO restent conservées. La direction
artistique, les symboles, la palette, les règles de zoom, le DEM Mapzen et le
chargement Flutter `MapLibreJsSource.cdn()` sont repris.

**Ne pas utiliser NoWave pour la navigation officielle.** Les objets OSM ne
constituent pas un inventaire nautique officiel ni une vérification sur le terrain.

## Inventaire de l'architecture

| Mode | Données affichées | Protection de la mer |
| --- | --- | --- |
| DEMO_FICTIVE | Bathymétrie, île, côte et objets synthétiques à 0°/0° ; DEM Mapzen externe réel | Masque raster propre à la démo ; île opaque car elle n'existe pas réellement |
| RELIEF_REAL_PREVIEW | Mapzen réel uniquement ; aucune bathymétrie ou objet DEMO | Masque raster approximatif calculé depuis le DEM, limité à Marseille–Cassis |
| CASSIS_REAL | Côte/objets OSM, bathymétrie SHOM, Mapzen terrestre | Polygone d'eau vectoriel dérivé du trait de côte OSM, au-dessus du hillshade |
| DONNEES_FOURNIES | Archive MVT normalisée et raster fournis | Contrat de sources fourni, indépendant du pilote |

`tools/build_style.py:build_cassis()` réutilise les couches visuelles approuvées
et remplace les sources. L'ordre est adapté au masque vectoriel : terre,
hillshade, masque d'eau, bathymétrie réelle puis isolignes/objets. Le serveur
`--real-cassis` sélectionne ce style et refuse les URL des assets fictifs.
Le POC lit `nowave:data_mode=CASSIS_REAL` pour valider la provenance ;
l’affichage reste plein écran, sans bandeau permanent.
La source de vérité reste le générateur ; `cassis-style.json` est son résultat.

## Préparation et lancement

Depuis la racine du dépôt :

```bash
python3 -m venv cartography/.venv
cartography/.venv/bin/pip install -r cartography/requirements-cassis.txt
cartography/.venv/bin/python cartography/tools/prepare_cassis.py
cartography/tools/build_vector_tiles.sh
cartography/.venv/bin/python cartography/tools/build_bathymetry_tiles.py \
  --input cartography/assets/cassis-bathymetry.png --bbox 5.515 43.19 5.555 43.225 \
  --output cartography/tiles/bathymetry/cassis --min-zoom 10 --max-zoom 14
python3 cartography/tools/build_style.py
python3 cartography/server.py --real-cassis
```

Puis :

```bash
cd map_poc
flutter run -d chrome --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Sans `--real-cassis`, le serveur continue de lancer la démo. `--center LON LAT`
et `--zoom Z` restent disponibles. Le POC n'est pas migré dans l'application métier.

Le cache brut reste par défaut dans `~/.cache/nowave-cassis`, hors du dépôt.
`--cache /chemin` permet de le déplacer. Recalcul depuis ce cache sans réseau :

```bash
cartography/.venv/bin/python cartography/tools/prepare_cassis.py --offline
```

Les sources chargées par Flutter sont les tuiles MVT issues du MBTiles Cassis,
le polygone d'eau local, les tuiles PNG XYZ bathymétriques et les assets graphiques
habituels. Mapzen et MapLibre CDN nécessitent encore Internet. La préparation
nécessite Internet pour OSM et SHOM ; aucune clé n'est utilisée par ces scripts.

## Sources et licences

| Dataset | Source | Licence / attribution | Zone / résolution | Utilisation / limites |
| --- | --- | --- | --- | --- |
| Mapzen Terrain Tiles | [AWS Open Data](https://registry.opendata.aws/terrain-tiles/) et [notices Tilezen](https://github.com/tilezen/joerd/blob/master/docs/attribution.md) | Crédits des producteurs dans `assets/mapzen-attribution.html` et `relief.attribution` | Tuiles Terrarium 256 px, z≤15 | Relief terrestre discret ; données externes, inchangées |
| OpenStreetMap | [Overpass](https://overpass.kumi.systems/api/interpreter), données inspectées avec tags et métadonnées | [© OpenStreetMap contributors, ODbL 1.0](https://www.openstreetmap.org/copyright) | Cassis et abords ; précision et dates variables | Côte, marina, pontons, épi, feux et occupation du sol ; les objets absents restent absents |
| SHOM HOMONIM Golfe du Lion–Côte d'Azur | [Produit officiel](https://diffusion.shom.fr/donnees/bathymerie/mnt-facade-gdl-ca-homonim.html), [DOI](https://doi.org/10.17183/MNT_MED100m_GDL_CA_HOMONIM_WGS84) | Licence Ouverte 2.0 ; « Shom, 2015. MNT Bathymétrique de façade du Golfe du Lion–Côte d'Azur (Projet Homonim) » | WGS84, 0,001° (≈111 m nord-sud, ≈81 m est-ouest à Cassis), PBMA | Approches/régional, jamais une précision portuaire ; cellules NoData conservées |
| SHOM levé S201300200 | [DOI du levé](https://doi.org/10.17183/S201300200), métadonnées ISO locales | Licence Ouverte 2.0 ; « Shom, levé bathymétrique S201300200 » | Acquisition 30/09/2007–12/07/2013 ; lidar, semis de sondes ZH assimilé PBMA | Sondes réellement présentes dans la bbox, agrégées sur une grille de 10 m ; ce pas n'est pas une garantie de précision de 10 m |
| Catalogue des levés | [WFS officiel](https://services.data.shom.fr/INSPIRE/wfs?service=WFS&request=GetCapabilities) | SHOM / Licence Ouverte 2.0 | Après 2005, puis 1990–2005 | Emprises interrogées et intersectées géométriquement ; une emprise catalogue seule ne prouve pas la présence de sondes |

La partie OSM normalisée conserve son attribution et sa licence ODbL ; les
profondeurs SHOM conservent leur licence séparée. Les dates et sources de chaque
objet sont dans `osm_tags`, `osm_id`, `osm_timestamp`, `retrieved_at` et `source`.
`data/cassis/manifest.json` fournit l'inventaire effectivement importé et les
statistiques de couverture ; les fichiers ISO documentent unités et références.
La notice française du levé contient un DOI différent dans une phrase de citation ;
le pilote utilise son identifiant et son DOI concordants `S201300200`, également
présents dans la notice anglaise, et conserve la notice originale.

## Extraction, couverture et précision

Emprise de sortie : **5,515–5,555° E / 43,190–43,225° N**, environ 3,2 × 3,9 km.
La requête OSM possède un léger tampon afin de fermer correctement le littoral.
Les lignes côtières OSM sont orientées terre à gauche, polygonisées puis fermées
uniquement sur les bords de l'emprise. Aucun contour côtier n'est déduit d'une
altitude DEM. Le masque marin conserve cette géométrie vectorielle à tous les zooms.

Les services publics SHOM accessibles ici proposent des paquets non découpés :
HOMONIM ≈89,5 Mo ; levé lidar ≈838 Mo compressés / 2,73 Go XYZ. Ils ne fournissent
pas, via le WFS d'emprises, les sondes dans une bbox. Le script lit le levé par
HTTP Range, décompresse par flux et ne garde que les points de Cassis : **le XYZ
global n'est jamais écrit ni chargé dans Flutter**. Cette préparation implique
néanmoins de transférer presque tout le paquet compressé indivisible. Les données
publiées et les données affichées sont exclusivement découpées à Cassis. Le cache
HOMONIM sert à découper la grille ; aucun raster méditerranéen n'est publié.

Les sondes sont agrégées par cellules métriques de 10 m, puis interpolées linéairement.
Une cellule n'est retenue que dans un triangle mesuré dont toutes les arêtes font
au plus 40 m et à moins de 20 m d'un point agrégé. Il n'y a aucune extrapolation
hors du support mesuré ; les trous restent visibles. La terre est exclue avec OSM.

HOMONIM sert de repli régional là où les quatre cellules nécessaires à l'interpolation
sont valides. Ce repli est interdit à l'intérieur de l'emprise OSM de la marina.
La couleur et les courbes viennent du même champ final `depth-grid.npz` ; la grille
`source` distingue 0=indisponible, 1=HOMONIM, 2=levé lidar. Les contours sont séparés
par provenance pour éviter un raccord de précision trompeur. Niveaux 2/5 m uniquement
sur les sondes, niveaux ≥10 m sur le repli régional. Aucun lissage décoratif ou bruit
synthétique n'est ajouté aux profondeurs réelles. Gris bleu signifie **profondeur
indisponible**, jamais une mesure de faible profondeur.

## Objets disponibles et absents

La sélection contient la marina `way/11407276`, des `man_made=pier`, un
`man_made=groyne` (rendu dans la famille visuelle digue), et les feux rouge/vert
`node/1420666230` / `node/1420666229`. Les jetées et quais dont les contours
font partie du littoral sont visibles comme terre/côte ; ils ne sont pas
requalifiés en objets `breakwater` ou `quay` en l'absence de ces tags.

Aucun bassin `waterway=dock`, quai `man_made=quay`, digue `man_made=breakwater`,
bouée, balise, épave ou mouillage identifié n'est inventé. Le label de port
est un point dérivé de la géométrie de marina OSM, pas une position mesurée.
Les formes surfaciques de pontons sont rendues par leur contour réellement mappé.
Les autres objets seamark non normalisables sont inventoriés, mais pas affichés.
Les restrictions de baignade présentes dans OSM restent hors du contrat du POC.

Les deux feux proviennent de contributions OSM citant une publication NGA de 2010.
Le champ libre d'information du feu vert mentionne un autre port : il est conservé
pour audit, mais n'est pas affiché comme une affirmation vérifiée. Le pilote affiche
les positions et caractéristiques structurées OSM ; il ne certifie pas leur actualité.

## Contrôles et captures

```bash
cartography/.venv/bin/python -m unittest discover -s cartography/tests -v
npm test --prefix cartography
cd map_poc
flutter analyze
flutter test
flutter build web --release
cd ..
# Servir map_poc/build/web sur 8766, serveur --real-cassis sur 8765.
npm run test:cassis --prefix cartography
git diff --check
```

Le contrôle Chromium utilise la vraie application Flutter et son CDN actuel.
Il vérifie les fichiers locaux, les tuiles DEM, les couches rendues, le pan/zoom,
les erreurs JS/MapLibre et compare les pixels marins avec/sans hillshade.
Le contrôle exclut 2 pixels de bord côtier et 45 pixels du pied d'interface
d'attribution, qui change automatiquement lorsqu'une couche est masquée.

- [Approche](previews/cassis-real/01-cassis-approach.png)
- [Port](previews/cassis-real/02-cassis-port.png)
- [Détail marina](previews/cassis-real/03-cassis-marina-detail.png)

Les résultats mesurés, tailles des fichiers, limites restantes et l'état Git sont
consignés dans [CASSIS_REVIEW.md](CASSIS_REVIEW.md).

## Compatibilité avec le pipeline régional

L’entrée générique conserve la recette numérique Cassis et ses fichiers validés :

```bash
.venv/bin/python cartography/tools/prepare_region.py --region cassis --offline
cartography/tools/build_vector_tiles.sh cartography/data/cassis/features.geojson cartography/tiles/vector/cassis.mbtiles
.venv/bin/python cartography/tools/build_bathymetry_tiles.py \
  --input cartography/assets/cassis-bathymetry.png --bbox 5.515 43.19 5.555 43.225 \
  --output cartography/tiles/bathymetry/cassis --min-zoom 10 --max-zoom 14
python3 cartography/server.py --region cassis
```

La première commande demande le cache Cassis complet ; sans `--offline`, elle
conserve l’acquisition historique explicite. `prepare_cassis.py` et
`--real-cassis` restent compatibles. Le centre du manifest validé
`[5.536,43.2105]` reste volontairement inchangé, même si la configuration
`cassis.json` contient `[5.535,43.2075]`. Le nouveau pipeline régional utilise
le centre de sa configuration. Une modification de caméra Cassis doit faire
l’objet d’une revue visuelle séparée.

La référence `tests/fixtures/cassis-baseline.json` fige le style, les types et
comptages d’objets, la palette et les empreintes des sorties réelles existantes.
Elle ne doit être actualisée qu’après revue explicite d’un changement Cassis.
