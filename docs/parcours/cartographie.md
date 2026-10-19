# Parcours — Carte maritime et consultation des signalements

**Référence :** `dev@6b54aa8` (19/10/2026). Correctif [FIX T13 / NW-166](https://linear.app/blueway/issue/NW-166) ; tickets NW-111, NW-114 et NW-157.

## Parcours

1. Flutter affiche la carte via le SDK Mapbox, conserve les interactions de zoom et de déplacement et exploite la localisation du téléphone lorsqu'elle est autorisée.
2. Le backend expose les tuiles vectorielles NoWave : `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt`. Les paramètres `category` et `report_id` permettent des sélections ciblées.
3. Le mobile affiche les marques et clusters représentés dans les tuiles. La sélection d'un signalement provoque la lecture des données actuelles via `GET /api/v1/reports/{report_id}`.
4. Une notification FCM peut ouvrir directement la carte sur le signalement ciblé, avec cadrage de celui-ci et de la position disponible du téléphone. Les détails complets sont lus auprès de l'API ; les coordonnées du push ne doivent pas être considérées comme source d'autorité.

Le fond actuellement décrit dans `mobile/README.md` est **Mapbox Standard** ; le fond marine MapTiler cité dans certaines spécifications doit faire l'objet d'un alignement technique distinct avant d'être annoncé comme livré. La couche NoWave MVT est séparée du fond cartographique.

## Expiration et cache — FIX T13 (NW-166)

- **Règle métier serveur :** `expires_at = observed_at + 24 h`. Les nouvelles requêtes cartographiques excluent les signalements qui ne sont plus actifs ou qui sont expirés à l'heure serveur.
- **Contrat HTTP MVT observé :** `Cache-Control: private, max-age=15, must-revalidate` et `Vary: Authorization`, dans `backend/app/api/routes/map_tiles.py`.
- **Effet visible :** une tuile précédemment reçue peut garder à l'écran un signalement désormais expiré. `max-age=15` règle le cache HTTP, **pas un délai maximal garanti de disparition dans Flutter** ; il dépend aussi du moment de rafraîchissement de la couche et de la politique de cache du SDK.
- **Décision :** aucun changement de TTL, d'actualisation Flutter ou de schéma de données n'est engagé dans ce correctif documentaire.

## Code et validation

- Backend : `backend/app/api/routes/map_tiles.py`, `backend/app/application/services/map_query.py`, `backend/app/infrastructure/repositories/postgresql_map_tile_repository.py`.
- Mobile : `mobile/lib/features/map/`, `mobile/lib/core/location/`.
- Tests présents : `backend/tests/api/test_map_tiles.py`, `backend/tests/database/test_map_tile_cache.py`, `mobile/test/features/map/`.

La présence des tests ne confirme ni leurs résultats à cette révision ni la synchronisation visuelle réelle sur Android/iOS. Vérifier séparément un signalement avant/après expiration sur le serveur et son délai d'effacement sur téléphone ; noter les deux horodatages.