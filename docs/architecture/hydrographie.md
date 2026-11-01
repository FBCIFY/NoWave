# Hydrographie

Les courbes relient des profondeurs publiées ; les sondes affichent une valeur
ponctuelle ou une cellule modélisée ; les dangers décrivent rochers, épaves et
obstructions. Une couleur de raster ne produit aucune profondeur.

## Profondeurs et datums

Les géométries sont en WGS84, longitude puis latitude. Les profondeurs sont
normalisées en mètres et conservent leur unité, valeur et référence d'origine.
Le datum fixe la référence verticale : deux valeurs avec des datums
incompatibles ne sont pas fusionnées. Un datum absent reste
inconnu ; une hauteur n'est pas interprétée comme une profondeur.

Les sondes NOAA gardent les valeurs ponctuelles publiées, y compris les décimales.
Les [cellules EMODnet](profondeurs-emodnet.md) restent des valeurs modélisées sous LAT.
Les courbes EMODnet 2022 sont généralisées au 1:500000, sans datum précisé dans
cette couche : elles ne donnent pas du détail portuaire.

Chaque objet conserve les précisions, dates et échelles réellement fournies.
Une collecte récente ne rend pas une observation ancienne plus précise.

## Rendu

Les lignes de courbe restent visibles même si leurs étiquettes sont masquées
par collision. Les sondes NOAA sont sélectionnées par cellule et datum compatible :
la moins profonde passe en premier, puis la précision publiée et l'identité stable.
Mapbox peut encore masquer des labels en collision.

Les rochers utilisent l'état `WATLEV` publié. Une obstruction n'est pas reclassée
en rocher à partir de son nom. Les dangers linéaires ou surfaciques gardent leur
forme, avec un contour ; ils ne deviennent pas des points.

Courbes et sondes sont sous les marques et dangers ; les signalements restent
au-dessus. Un appui long donne accès aux objets ponctuels proches, même si leur
symbole est masqué.

L'affichage ne remplace pas les cartes nautiques officielles et ne permet pas
de calculer une marge sous quille.
