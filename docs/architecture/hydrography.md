# Courbes, sondes et dangers sous-marins

## Sources réellement consultées le 17 octobre 2026

| Source | Endpoint / couche | Données / référence / licence |
|---|---|---|
| Shom | `https://services.data.shom.fr/INSPIRE/wfs`, `EPAVES_BDD_WFS:wrecks`, `EPAVES_BDD_WFS:obstrn` | Objets ponctuels 2D, WGS84. Brassiage en m, positif vers le bas, zéro des cartes marines; définition locale du datum non fournie. `precis_bra` décrit la qualité, `precis_loc` est une précision horizontale en m. CC BY-SA 4.0. |
| NOAA | `https://encdirect.noaa.gov/arcgis/rest/services/encdirect/enc_{scale}/MapServer` | ENC Direct: DEPCNT, SOUNDG, UWTROC, WRECKS, OBSTRN. Valeurs ENC en mètres. Code VERDAT conservé s'il existe, sinon inconnu. CC0-1.0. |
| EMODnet | `https://ows.emodnet-bathymetry.eu/wfs`, `emodnet:contours` | Contours **publiés dérivés du DTM**, version 2022 selon sa fiche, attribut `elevation` positif vers le bas en m. Produit UE, CC BY 4.0. Aucun PNG n'est lu par ce pipeline. |

Références primaires : [Shom et citation DOI](https://diffusion.shom.fr/donnees/epaves.html),
[spécification Shom](https://services.data.shom.fr/static/specifications/spec_epaves_et_obstructions.pdf),
[NOAA ENC Direct](https://nauticalcharts.noaa.gov/data/gis-data-and-services.html),
[NOAA, unités des sondes](https://nauticalcharts.noaa.gov/updates/introducing-new-enc-direct-to-gis/),
[métadonnées des contours EMODnet](https://sextant.ifremer.fr/geonetwork/srv/api/records/4f7ab468-f4b9-4c2c-8d3b-49a375cf9964),
[conditions EMODnet](https://emodnet.ec.europa.eu/en/terms-use-emodnet-online-services-data-and-data-products).

Le GetCapabilities WFS Shom et les DescribeFeatureType ont été inspectés : pas de
DEPCNT/SOUNDG/UWTROC public identifié. Les couches `LEVES_BATHY_*` décrivent des
emprises de levés, pas des sondes. Les [levés XYZ](https://diffusion.shom.fr/leves-bathy.html)
sont un autre produit : quatre levés officiels sont désormais intégrés par
`shom-surveys` (voir le correctif ci-dessous), avec couverture partielle de Toulon.
Les ENC Shom commerciales ne deviennent pas une source ouverte par leur présence
au catalogue. Pas de rochers français qualifiés par ces couches WFS. Une obstruction Shom n'est jamais
promue en rocher à partir de son texte ou de sa proximité avec une roche.

### Limite importante du repli français

La fiche exacte EMODnet annonce une généralisation à **1:500000**, avec suppression
des petits contours fermés, y compris des hauts-fonds. Elle cite le logiciel
propriétaire GGSgc pour la génération automatique. Le jeu n'est donc pas une
représentation hydrographique exhaustive et n'est pas un ENC. Le DTM de cette
génération utilise un pas de 1/16 minute d'arc (environ 116m nord-sud, 85m est-ouest
à 43°N); NoWave ne réinterpole aucune grille. Les lignes publiées sont consommées
telles quelles, puis simplifiées et découpées pour l'affichage. La fiche annonce
50/100/200/500/1000/2000/5000/7000m; le capabilities en liste sept sans 7000m.
Seules les valeurs réellement retournées deviennent des features. Le datum exact
n'est pas un champ de cette couche : il reste inconnu, même si le DTM général est
[normalement référencé au LAT](https://emodnet.ec.europa.eu/en/bathymetry).
Aucun détail de port ou contour 2/5/10m n'est inventé pour combler ce manque.

### Catalogue NOAA vérifié

`hydro_layers.json` conserve 42 couches réellement inspectées : 39 couches d'objets
et trois couches de datum, sur general/coastal/approach/harbour/berthing. L'overview
ne fournit pas ces classes dans le service consulté et n'est pas nécessaire à Z12.
Exemple harbour : contour 104; sonde 76; rocher 34; épave 36/158; obstruction
33/99/156; datum 224. Les IDs des autres échelles restent dans le catalogue.
Champs : `VALDCO`, `Z` ou Z par coordonnée, `VALSOU`, `CATWRK`, `CATOBS`, `WATLEV`,
`VERDAT`, `QUASOU`, `SOUACC`, `DSNM`, `SORIND`, `SORDAT`, `SCAMIN`, `OBJNAM`.
`SORDAT` reste la date de source, jamais une date de révision supposée.

Les cellules `enc_coverage/MapServer/1..5` choisissent spatialement l'échelle la
plus détaillée; `CATCOV=2` n'est pas une couverture. Hors de ces cellules détaillées,
la géométrie d'une échelle plus générale subsiste. Cette sélection de cartes n'est
pas une fusion par profondeur. Les fragments gardent l'échelle et la cellule.
Un `Sounding_Datum_area` ne complète un VERDAT absent que dans la même cellule et
échelle, s'il couvre tout le fragment et que les références candidates concordent.
La provenance et le lien de cette zone sont alors ajoutés. Aucun datum de zone
n'a été trouvé aux points Miami/Cape Florida échantillonnés : ils restent inconnus.

`backend/tools/refresh_hydro_catalog.py` rafraîchit explicitement les métadonnées
sans télécharger de pyramide. Examiner les changements avant déploiement.
Les anciens fournisseurs/cartes restent inchangés. Pas de nouvelle intégration
CHS/AHO/AMSA/LINZ ni de couverture mondiale annoncée.

## Contrat NoWave

Trois modèles spécialisés héritent de `HydroFeature` / `MarineFeature` :
`DepthContour`, `Sounding`, `UnderwaterHazard` (rock / wreck / obstruction).
Champs communs : identité stable, géométrie WGS84, source, provenance, nom, échelle,
SCAMIN, date source, attributs source JSON, géométrie source, licence, dérivation.
Profondeurs : `value_original`, `unit_original`, `value_m`; références :
`vertical_datum`, `sounding_datum`, `datum_reference`; qualité : `quality`,
`accuracy` verticale en m, `horizontal_accuracy` en m. Null au modèle signifie
inconnu; MVT omet ces propriétés null car ses attributs sont scalaires.

Conversions explicites : m ×1, ft ×0.3048, fathom ×1.8288. Unité non vérifiée avec
valeur : rejet. Les services intégrés fournissent déjà des mètres. Les valeurs
négatives restent négatives; `HEIGHT` n'est jamais converti en profondeur. Pour
NOAA Point, le Z attributaire évite le bruit flottant du transport XYZ; une
contradiction >1e-6 est rejetée. Les MultiPoint sont éclatés en échantillons indexés
avec **leur propre Z ou leur propre valeur de tableau**, jamais un Z scalaire commun.

Courbes : LineString/MultiLineString. Sondes : Point après éclatement MultiPoint.
Dangers : Point/MultiPoint/LineString/MultiLineString/Polygon/MultiPolygon.
Les lignes/surfaces de dangers restent des lignes/surfaces; pas de centroïde.
Le modèle garde catégorie, niveau d'eau et brassiage; un minimum Shom n'est annoncé
que si sa qualification est `brassiage minimal connu`. Les champs bruts conservent
les qualifications restantes. Aucune classe de danger n'est calculée par seuil.

Fusion conservatrice : même modèle, même famille de danger, identité corroborée,
géométrie de même type et quasi identique (1cm), profondeur, unité, datum,
qualité et attributs identiques. Un objet distinct ou un doute reste distinct.
La proximité ou une même valeur de profondeur ne suffisent pas.

## Endpoints et performance

| Endpoint XYZ `.pbf` | Source-layer | Seuil backend / source mobile | Zoom natif mobile |
|---|---|---|---|
| `/api/v1/map/depth-contours/{z}/{x}/{y}.pbf` | `depth_contour` | 12 | 14, overzoom ensuite |
| `/api/v1/map/soundings/{z}/{x}/{y}.pbf` | `sounding` | 14 | 16, overzoom ensuite |
| `/api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf` | `underwater_hazard` | 12 | 14, overzoom ensuite |

Ces routes acceptent Z0–16, retournent un MVT vide valide sous leur seuil **avant
la sélection et tout appel provider**. Les routes historiques restent Z0–14.
Le MVT utilise EPSG:3857, extent 4096, buffer 64 unités, clipping dimensionnel.
Seules les courbes sont simplifiées, tolérance 1 unité MVT avant clipping :
0.125 pixel de tuile 512px; overzoom ×8 à Z17 depuis Z14 = 1 pixel. Aucun danger
ni échantillon n'est simplifié. Les contacts tangentiels de dimension inférieure
sont écartés, les fragments de même dimension sont conservés.

Les requêtes de courbes/dangers partagent le parent Z12; celles des sondes le
parent Z14, avec marge 100m. La couverture NOAA est partagée au parent Z12.
Requêtes paginées NOAA, au plus 4×1000 objets/classe; Shom/EMODnet au plus 2000.
Troncature et échecs sont déclarés dégradés; panne totale sélectionnée = 503 et
pas de faux vide mis en cache. Hors couverture intégrée = vide, sans exhaustivité.
Les erreurs nationales ne bloquent pas la carte Flutter.

Transport/cache HTTP commun existant : 8 requêtes simultanées, 4s HTTP, single
flight, SQLite persistant, plafond 512MiB, corps limité à 8MiB, TTL 6h national,
cooldown 429/503. Budget provider global 14s. Cache MVT commun : 512 entrées/32MiB,
300s ou 15s dégradé. Compteurs HTTP `network_requests` / `cache_hits` pour mesurer
les appels réels. Le programme `backend/tools/probe_hydrography.py --output <dir>`
mesure les tuiles centrales/voisines et leur répétition, sans requête OSM préalable.

## Sélection et style

Courbes principales (major) : zéro ou multiples exacts de 10m réellement publiés.
Les autres sont minor. À Z12 : major + profondeurs publiées >=3m; Z13 : ajout des
valeurs >=1m; Z14 : toutes. Ces seuils **sélectionnent** les objets : ils ne créent
aucune ligne. Cela conserve à Z12 les contours NOAA réels de 3.6m et 5.4m issus
notamment d'anciennes graduations en pieds, sans les arrondir à 5m.

Les couches hydrographiques visibles utilisent désormais `minZoom=13` selon `MarineZoom.depths`; largeur major .95/minor .55, opacité
.72/.48, bleu-gris #507F99. Étiquettes natives le long des contours, répétées tous les 160px, taille
interpolée 10.5/11.5/12.5/13.5px aux zooms 12/14/16/18, halo fin .6px. Sondes
à partir de 13, même taille adaptative, sans pastille, collisions activées. Grilles
Mercator mondiales imbriquées (tailles détaillées ci-dessous) : choisir la sonde la moins
profonde de chaque cellule, puis précision publiée et ID stable. Les datums connus
incompatibles restent dans des groupes séparés. Les vainqueurs peu profonds restent
retenus aux zooms suivants; le SDK écarte les collisions résiduelles.

Les rochers ont des variantes distinctes pour dry / drying / awash / submerged /
unknown, sélectionnées uniquement par WATLEV publié. Épave et obstruction ont leurs
propres icônes et les géométries étendues ont un trait/contour discret. Ces symboles
NoWave ne prétendent pas être une bibliothèque certifiée INT1.

Ordre visuel : bathymétrie + texture BOTTOM; courbes/sondes MIDDLE puis ouvrages
MIDDLE (docks BOTTOM); dangers TOP; aides fixes puis bouées TOP; reports sans slot,
GPS et commandes au-dessus. L'ordre brut renvoyé par `getStyleLayers` mélange les
slots : vérifier aussi `slot`, pas uniquement les indices. Images et sources sont
idempotentes, réinstallées au style reload; erreurs de sources facultatives isolées.
Les données dérivées du Shom restent sous CC BY-SA 4.0; leur nouvelle famille ne
contient pas d'OSM. Les licences de chaque apport sont conservées sur les features
et dans les crédits, sans remplacer la licence historique des autres familles.

## Correctif du 17 octobre 2026

Les contours et les sondes portent `depth_label`, issu de `value_m` sans arrondi
au décimètre. Le contrat mobile hydrographique `?v=3` évite la réutilisation de
tuiles natives antérieures dépourvues de ce champ. Les courbes et leur texte ont
le même filtre d'éligibilité (Z12, valeur publiée, seuil de sélection).
Les contours EMODnet 2022 au 1:500000 sont normaux à Z12–13, atténués à Z14
(opacité majeure .32, mineure .22) et exclus dès Z15, texte compris. Les ENC NOAA
restent éligibles aux zooms locaux. Aucune source française plus précise ne
remplace les lignes EMODnet dans cette livraison.

Les levés XYZ Shom sont désormais une **source distincte** des épaves Shom :
`shom-surveys`, Licence Ouverte 2.0, profondeur publiée en mètres / LAT explicite.
7 795 vrais points : 430 dans trois fichiers officiels intégraux et 7 365
lignes originales sélectionnées hors ligne dans S201300200 ; provenance par DOI,
archive et checksum, identifiant levé + numéro de ligne, dates d'acquisition et
révision. Les attributs bruts de chaque sonde contiennent sa ligne XYZ. La
précision individuelle reste inconnue. Catalogue initial limité à Toulon, avec des mesures dans les grands bassins
et les approches ; aucun remplissage des bassins ou autre port sans mesure.
Voir `backend/app/infrastructure/marine/data/shom-surveys/README.md`.

La sélection des sondes utilise des grilles Mercator mondiales emboîtées. Les
cartes NOAA `harbour`/`berthing` et les levés côtiers intégrés utilisent des
cellules de 64/32/32 px à Z14/15/16 ; les autres usages 128/64/64 px. Le minimum
par cellule et référence compatible est prioritaire, puis précision publiée,
priorité source et ID stable. Les références inconnues de cellules ENC/datasets
distincts restent séparées. Cette densité dépend du type de source/cartographie,
pas d'une frontière de port inventée. À Z17 la source de sondes Z16 est surzoomée,
les chiffres continuent de grandir légèrement et les collisions restent natives.

Les obstructions non sous-typées utilisent une petite enceinte ouverte
interrompue ; les roches une croix et les variantes d'état explicitement publié ;
les épaves une coque/mât. Un type inconnu est un tiret discret. Le texte libre
Shom n'est jamais utilisé pour promouvoir une obstruction en roche.


Le levé S201300200 est mixte lidar topographique/bathymétrique. L'import initial
exclut explicitement ses observations négatives (relief terrestre/découvrant),
**avant** la sélection du minimum : pas de point de toiture négatif utilisé comme
profondeur minimale d'un bassin. Il ne transforme ni une altitude ni un pixel en
sonde. Les lignes conservées publient déjà une profondeur positive en m/LAT.
99 611 561 observations dans le fichier original ; 11 672 dans l'emprise
5.88–5.96 E / 43.08–43.13 N ; 7 365 mesures non négatives retenues sur la grille
mondiale Z16/32px. Aucun point moyen ou centre de cellule n'est créé. Le numéro
de ligne d'origine, l'archive et les SHA-256 permettent de retrouver chaque valeur.
Le script `backend/tools/import_shom_survey.py` est hors ligne (py7zr + awk/mawk),
avec checksum de l'archive, contrôle de l'en-tête m/LAT, licence dans le XML,
comptage et borne de 100 000 cellules. Le serveur utilise un index spatial du
petit catalogue résultant ; il ne télécharge ni ne parcourt le nuage complet.

Une ligne n'est rendue que si son ID a un label réellement placé par Mapbox dans
la vue. Les chiffres sont placés par `symbolPlacement=line`, spacing 160px,
collisions natives ; une interrogation après changement de placement ou à
l'arrêt de la carte active `feature-state.label_visible` pour ces lignes seules.
Les mouvements invalident l'ancien placement, les requêtes périmées sont écartées,
les échecs restent masqués, et un reload recrée sources/images/layers sans doublon.
Une ligne trop courte ou dont tous les chiffres entrent en collision est omise ;
aucun chiffre n'est forcé au-dessus des aides à la navigation.
