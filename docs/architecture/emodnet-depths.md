# Profondeurs EMODnet

Les chiffres européens viennent du DTM EMODnet 2024 : des cellules modélisées,
parfois interpolées, et non des sondes originales. Le backend lit ERDDAP à la
demande. NOAA fournit ses sondes hors couverture EMODnet ; une panne EMODnet
ne déclenche pas de bascule vers NOAA.

## Grille et valeurs

Le produit `bathymetry_dtm_2024` utilise une grille WGS84 de 1/960°,
soit 1/16 minute d'arc et environ 116 m nord–sud. Son emprise va d'environ
36° O à 43° E et de 15° N à 90° N. `elevation` est en mètres par rapport au LAT,
négatif sous ce niveau. Seules les valeurs finies strictement négatives deviennent
`value_m = -elevation` ; les valeurs manquantes ou terrestres sont exclues.

Un label inférieur à un mètre affiche `<1`. Les autres sont arrondis au mètre,
demi-unités vers le haut : 12,4 → 12 ; 12,5 → 13. La valeur numérique d'origine
reste conservée, avec `nature=modeled_grid_cell`, les indices et métadonnées
publiées. Aucune précision individuelle n'est déduite du modèle.

Crédit : EMODnet Bathymetry Consortium (2024), *EMODnet Digital Bathymetry
(DTM 2024)*, [DOI du produit](https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1),
CC BY 4.0. NoWave sélectionne les cellules, convertit le signe et arrondit les labels.

## Sélection

Les indices suivent une grille mondiale fixe : pas de 32 cellules à Z12,
16 à Z13, 4 à Z14, 2 à Z15 et 1 à Z16, avec au plus 64 cellules par tuile.
Chaque centre appartient à une seule tuile. Aucun appel n'est fait sous Z12 ;
zoomer au-delà de Z16 n'ajoute aucune mesure. Le budget mobile peut réduire
la résolution demandée.

## Erreurs fournisseur

Le CSV doit contenir la grille complète avec les bons champs, unités et
coordonnées. Troncature, doublon ou valeur malformée fait échouer la réponse.
Un changement du produit demande une mise à jour de l'adaptateur.

Le client limite les appels à deux simultanés par processus, espacés d'au moins
250 ms, avec une échéance de 10 s et un corps de 256 Kio maximum. Il temporise
5 s après une erreur réseau, 30 à 120 s après 429/503 selon `Retry-After`.
Les corps CSV ne sont pas stockés sur disque ; une déconnexion annule le travail.
Une panne n'est jamais remplacée par un faux résultat vide.

Voir les [contrats API](../API.md) pour les réponses HTTP et les
[règles mobiles](marine-zoom-persistence.md) pour le cache. Ces valeurs ne
garantissent ni précision portuaire ni marge sous quille.
