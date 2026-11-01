# Profondeurs EMODnet

Les chiffres européens viennent du DTM EMODnet 2024. Ce sont des cellules
modélisées, parfois interpolées, et non des sondes ponctuelles originales.
Le backend sélectionne ces cellules à la demande ; le mobile reçoit du GeoJSON.
La route MVT reste disponible.

## Flux

```text
MarineViewport → /api/v1/map/marine-features/soundings/{z}/{x}/{y}.geojson
              → MarineTileService → EmodnetDepthProvider → ERDDAP CSV
              → cellules validées → GeoJSON WGS84 → source Mapbox nowave-soundings
```

La route `/api/v1/map/soundings/{z}/{x}/{y}.pbf` utilise le même fournisseur et
les mêmes propriétés dans la couche MVT `sounding`. Le cache final distingue
les formats. NOAA fournit les sondes dans sa propre couverture, hors EMODnet ;
une panne EMODnet ne déclenche pas de bascule vers NOAA.

## Contrat du produit

| Paramètre | Valeur |
| --- | --- |
| Produit | `bathymetry_dtm_2024` sur ERDDAP EMODnet |
| Grille | 72 000 latitudes × 75 840 longitudes, centres en WGS84 |
| Résolution native | 1/960°, soit 1/16 minute d'arc ; environ 116 m nord–sud |
| Emprise | Environ 36° O à 43° E, 15° N à 90° N |
| `elevation` | Mètres par rapport au LAT, négatif sous le niveau de référence |
| Métadonnées | `value_count`, `interpolation_flag`, `cdi_index` |
| Licence | CC BY 4.0 |

Crédit : EMODnet Bathymetry Consortium (2024), *EMODnet Digital Bathymetry
(DTM 2024)*, [DOI du produit](https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1).
NoWave sélectionne les cellules, convertit le signe et arrondit les labels.
Les constantes et la validation sont dans
[emodnet_depths.py](../../backend/app/infrastructure/marine/emodnet_depths.py).

Le CSV doit contenir la grille demandée complète, avec les bons noms de champs,
unités et coordonnées. Troncatures, doublons, nombres malformés et cellules
étrangères font échouer la réponse. Les constantes décrivent le produit 2024 ;
un changement du schéma ou de la grille demande une mise à jour de l'adaptateur.

## Sélection des cellules

| Zoom de requête | Pas dans la grille native |
| --- | --- |
| Z0–11 | Aucun appel |
| Z12 | 32 cellules |
| Z13 | 16 cellules |
| Z14 | 4 cellules |
| Z15 | 2 cellules |
| Z16 | 1 cellule |

Les indices sont alignés sur la grille mondiale, avec au plus 64 cellules par
tuile. Chaque centre appartient à une seule tuile : ouest inclus, est exclu ;
sud exclu, nord inclus. Le zoom au-delà de Z16 ne crée pas de nouvelles mesures.
Le budget du mobile peut demander une résolution inférieure au zoom caméra.

Seules les élévations finies strictement négatives deviennent des profondeurs :
`value_m = -elevation`. Les valeurs manquantes, nulles ou terrestres sont exclues.
Une profondeur inférieure à un mètre affiche `<1`. Les autres labels sont
arrondis au mètre, demi-unités vers le haut : 12,4 → 12 ; 12,5 → 13.
La valeur numérique originale n'est pas arrondie.

Les objets conservent `nature=modeled_grid_cell`, le dataset, le datum LAT, les
indices globaux, l'élévation signée originale et les métadonnées disponibles.
Aucune date d'observation ni précision individuelle n'est déduite du modèle.

## Réseau et cache

| Limite | Valeur |
| --- | --- |
| Requêtes ERDDAP simultanées | 2 par processus |
| Espacement des départs | Au moins 250 ms |
| Timeout HTTP | 6 s ; connexion et pool 2 s |
| Échéance fournisseur | 10 s, attente comprise ; enveloppe du service 14 s |
| Taille CSV décompressée | 256 Kio maximum |
| Après erreur réseau | Pause de 5 s |
| Après 429/503 | Pause de 30 à 120 s selon `Retry-After` |

Le client HTTP dédié ne stocke pas les corps CSV sur disque et ne relance pas
une requête en boucle. Seul le résultat final utilise le cache RAM partagé :
512 entrées, 32 Mio, TTL 300 s ; TTL 15 s pour un résultat dégradé.
Une déconnexion annule le travail, ferme la réponse HTTP et libère le sémaphore.
Une demande annulée ne remplit pas le cache.

## Réponses

| Cas | HTTP | `X-NoWave-Marine-Status` |
| --- | --- | --- |
| Cellules disponibles | 200 | `ok` |
| Zone couverte sans profondeur valide sélectionnée | 200 | `empty` |
| Hors couverture | 200 | `outside-coverage` |
| Sous le seuil de chargement | 200 | `below-minzoom` |
| Fournisseur indisponible ou CSV invalide | 503 | `unavailable` |
| XYZ invalide | 422 | — |
| Déconnexion détectée | 499, client déjà parti | — |

Les sondes GeoJSON et MVT portent `Cache-Control: no-store`, y compris en cas
de 503. Le résultat RAM côté serveur reste distinct de ce contrat HTTP.

Les labels apparaissent dès Z13. Leur nombre dépend aussi des collisions Mapbox,
pas seulement du nombre de cellules reçues. Les
[règles de chargement mobile](marine-zoom-persistence.md) fixent les budgets.
Ce modèle ne garantit ni passage sûr, ni précision portuaire, ni marge sous quille.
