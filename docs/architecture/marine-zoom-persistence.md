# Chargement et conservation des couches marines

`MarineViewport` charge la vue Mapbox, rotation, inclinaison et padding compris,
avec une marge d'une cellule. Les [contrats API](../API.md) décrivent les formats
et bornes des requêtes ; ce guide couvre le comportement mobile.

## Seuils

Les valeurs sont centralisées dans
[MarineZoom](../../mobile/lib/core/map/marine/marine_zoom.dart).

| Zoom caméra | Comportement |
| --- | --- |
| Z5 | Affichage du raster marin |
| Z6 | Préchargement des ports |
| Z8 | Affichage des ports |
| Z10 | Enrichissement portuaire et préchargement des marques/dangers |
| Z10–12 | Fondu des marques : 0 % à Z10, 50 % à Z11, 100 % à Z12 |
| Z12 | Préchargement des courbes et sondes |
| Z13 | Affichage des courbes, labels et sondes |

Les couches n'ont pas de seuil supérieur de disparition. Les courbes utilisent
une grille Z12 fixe ; les sondes peuvent atteindre Z16. Un zoom plus élevé ne
crée aucune mesure supplémentaire.

## Cache et remplacement

Le mobile garde au plus 64 snapshots et 12 Mio de JSON encodé, plus 8 000 points
retenus dans 4 Mio. Deux téléchargements GeoJSON peuvent tourner en parallèle.
Ces limites n'incluent pas toute la mémoire Dart, GPU et Mapbox.

Le centre visible passe avant les marges. Si le budget est dépassé, le client
réduit la résolution ou diffère le détail. Le fond mondial GEBCO reste présent.
Une cellule complète remplace sa zone ; les anciennes couvrent les trous restants
jusqu'à la relève ou leur sortie de la région utile.

Un résultat complet vide confirme l'absence de données. Une erreur ou un résultat
partiel vide conserve les données précédentes. Le client retente après environ
15–16 s, annule les requêtes dépassées et suspend le chargement en arrière-plan.
Le rechargement du style reconstruit les sources avec leur état conservé.

## Continuité du rendu

Les ports déjà visibles gardent leur priorité sur les nouveaux. Revenir sous
Z8 réinitialise cette sélection. Les cardinales et dangers isolés disposent de
couches autorisant le chevauchement ; les autres collisions restent actives.
L'appui long permet de consulter les objets ponctuels masqués. Les courbes et
leurs labels ont des collisions indépendantes.

GEBCO reste sous le détail raster EMODnet ; tous deux préchargent une résolution
inférieure avec `prefetchZoomDelta: 4`. Le détail conserve tuiles parentes, cache
disque et fondu. Un échec de chargement conserve l’ancienne tuile utile.

Les caches ne garantissent pas une conservation hors ligne illimitée.
