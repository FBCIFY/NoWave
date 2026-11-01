# Courbes, sondes et dangers sous-marins

Le backend normalise trois familles indépendantes : `DepthContour`, `Sounding`
et `UnderwaterHazard`. Le mobile les charge en GeoJSON et les dessine avec
Mapbox. Les routes MVT restent disponibles pour les outils et autres clients.

## Sources utilisées

| Famille | Source | Limite principale |
| --- | --- | --- |
| Courbes | NOAA ENC et contours EMODnet 2022 | EMODnet fournit des courbes généralisées au 1:500000, pas du détail portuaire |
| Sondes | EMODnet DTM 2024 dans sa couverture ; NOAA ailleurs | EMODnet fournit des cellules modélisées ; NOAA des valeurs ponctuelles publiées |
| Dangers | Épaves/obstructions Shom et objets NOAA | Une obstruction n'est pas reclassée en rocher à partir de son nom |

Les levés XYZ Shom conservés dans le dépôt sont archivés et exclus du fournisseur
de chiffres actuel. Les [sources et licences](marine-sources.md) regroupent les
crédits ; le [contrat EMODnet](emodnet-depths.md) détaille les cellules modélisées.

## Géométrie et profondeurs

Les géométries normalisées utilisent WGS84 : longitude puis latitude.
Les courbes sont des lignes ; les sondes sont des points. Un MultiPoint NOAA est
éclaté en échantillons avec la profondeur propre à chaque point. Les dangers
peuvent être ponctuels, linéaires ou surfaciques : un polygone reste un polygone.

Chaque objet conserve son identité, sa source, sa licence et les attributs
publiés : profondeur, unité, datum, précision, date source et échelle lorsqu'ils
existent. Une valeur absente reste inconnue. Les conversions explicites sont
mètre × 1, pied × 0,3048 et brasse × 1,8288 ; une unité non reconnue est rejetée.
Une hauteur n'est pas interprétée comme une profondeur.

Le rapprochement exige une identité corroborée, une géométrie compatible et des
attributs concordants. Deux objets proches ou de même profondeur restent
séparés si ces critères ne sont pas réunis. Les datums incompatibles ne sont
pas fusionnés.

## Routes et formats

Préfixe commun : `/api/v1/map/`.

| Famille | Snapshot mobile | Couche MVT de la route `{family}/{z}/{x}/{y}.pbf` |
| --- | --- | --- |
| `depth-contours` | `marine-features/depth-contours/12/{x}/{y}.geojson` | `depth_contour` |
| `soundings` | `marine-features/soundings/{z}/{x}/{y}.geojson`, Z10–16 | `sounding` |
| `underwater-hazards` | `marine-features/underwater-hazards/{z}/{x}/{y}.geojson`, Z10–14 | `underwater_hazard` |

Les trois familles produisent un résultat vide sous Z12, avant tout appel aux
fournisseurs. Les routes MVT acceptent Z0–16. Les snapshots sont limités à
6 000 objets et 4 Mio ; un dépassement échoue au lieu de tronquer silencieusement.
Un XYZ invalide répond 422 ; une panne totale répond 503. Une collecte partielle
est marquée `degraded`.

Le GeoJSON garde les coordonnées WGS84 sans quantification MVT. Les courbes sont
découpées sur une grille Z12 fixe, sans buffer, avec un identifiant de rendu
`identité_source@12/x/y`. Le MVT utilise Web Mercator, extent 4096 et buffer 64 ;
seules ses courbes sont simplifiées avant découpage.

## Rendu mobile

Les données de profondeur sont préparées dès Z12 et affichées dès Z13.
Les courbes déjà chargées restent disponibles au zoom avant ; leurs étiquettes
ont leurs propres collisions. Les courbes et sondes occupent le slot MIDDLE ;
les dangers et marques, le slot TOP. Les signalements restent au-dessus.

Les sondes NOAA sont sélectionnées sur une grille spatiale d'au moins Z14 : la
valeur la moins profonde est prioritaire par cellule et datum compatible, puis
la précision publiée et l'identité stable départagent les candidats. Le SDK
peut encore masquer des labels en collision. EMODnet conserve sa grille propre.

Les états de rocher viennent de `WATLEV` publié. Épaves et obstructions ont leurs
symboles dédiés ; les géométries étendues gardent un contour. Un appui long donne
accès aux objets proches, y compris lorsqu'un symbole est masqué.
Les [règles de conservation](marine-zoom-persistence.md) couvrent le cache mobile
et le rechargement du style.

Les courbes EMODnet sont généralisées et leur datum n'est pas précisé dans cette
couche. Une profondeur inconnue n'est jamais calculée à partir d'une couleur.
L'affichage ne convient ni à la navigation ni au calcul d'une marge sous quille.
