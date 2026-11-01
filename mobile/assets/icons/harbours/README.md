# Icônes de ports

Deux PNG NoWave transparents de 72 × 72 px :

| Fichier | Identifiant Mapbox | Catégorie |
| --- | --- | --- |
| `port.png` | `nowave-harbour` | Autres catégories de ports qualifiées |
| `marina.png` | `nowave-marina` | `marina` |

Le ratio Mapbox de 3 donne 24 points avant adaptation au zoom. Les données sont
préparées au zoom 6 et les icônes affichées au zoom 8 par `HarbourLayer`.
Les collisions et priorités suivent les règles de la couche.

`MarineIconImage` transmet les PNG encodés avec leurs dimensions réelles.
L’installation peut être répétée sans doublon ; elle reprend après une erreur
ou un rechargement du style.
