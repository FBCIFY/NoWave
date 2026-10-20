# Parcours — Carte maritime et consultation des signalements

**Référence :** `dev@e708880` (20/10/2026), après fusion de la PR #93. Correctif [FIX T13 (NW-166)](https://linear.app/blueway/issue/NW-166) ; tickets NW-111, NW-114 et NW-157.

## Parcours

1. Flutter affiche la carte via le SDK Mapbox, conserve les interactions de zoom et de déplacement et exploite la localisation du téléphone lorsqu'elle est autorisée.
2. Le backend expose les tuiles vectorielles NoWave : `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt`. Les paramètres `category` et `report_id` permettent des sélections ciblées.
3. Le mobile affiche les marques et clusters représentés dans les tuiles. La sélection d'un signalement provoque la lecture des données actuelles via `GET /api/v1/reports/{report_id}`.
4. Une notification FCM peut ouvrir directement la carte sur le signalement ciblé, avec cadrage de celui-ci et de la position disponible du téléphone. Les détails complets sont lus auprès de l'API ; les coordonnées du push ne doivent pas être considérées comme source d'autorité.

Le fond retenu reste **Mapbox**. `GlobeStyle` prépare un style local qui importe
Mapbox Standard ; les couches publiques de bathymétrie, hydrographie, ports et
balisage sont ajoutées par-dessus ce socle. La couche NoWave MVT authentifiée
reste distincte. Les évolutions de [NW-164](https://linear.app/blueway/issue/NW-164)
sont fusionnées dans la [PR #93](https://github.com/FBCIFY/NoWave/pull/93).

**Décision NW-187, confirmée par Vadim le 20/10/2026 :** conserver cette solution
Mapbox et les couches marines ; ne pas réactiver l'ancien fond MapTiler.
`MAPTILER_STYLE_URL` n'est plus utilisé. Les sources publiques peuvent passer
par `MARINE_API_BASE_URL`, sinon elles utilisent `API_BASE_URL`. La fusion ne
certifie ni le déploiement des routes marines ni une profondeur disponible
partout sur le globe ; la recette distante doit en vérifier la couverture.

## Expiration et cache - FIX T13 (NW-166)

- **Règle métier serveur :** `expires_at = observed_at + 24 h`. Les nouvelles requêtes cartographiques excluent les signalements qui ne sont plus actifs ou qui sont expirés à l'heure serveur.
- **Contrat HTTP MVT observé :** `Cache-Control: private, max-age=15, must-revalidate` et `Vary: Authorization`, dans `backend/app/api/routes/map_tiles.py`.
- **Effet visible :** une tuile précédemment reçue peut garder à l'écran un signalement désormais expiré. `max-age=15` règle le cache HTTP, **pas un délai maximal garanti de disparition dans Flutter** ; il dépend aussi du moment de rafraîchissement de la couche et de la politique de cache du SDK.
- **Décision :** aucun changement de TTL, d'actualisation Flutter ou de schéma de données n'est engagé dans ce correctif documentaire.

## Code et validation

- Backend : `backend/app/api/routes/map_tiles.py`, `backend/app/application/services/map_query.py`, `backend/app/infrastructure/repositories/postgresql_map_tile_repository.py`.
- Mobile : `mobile/lib/features/map/`, `mobile/lib/core/location/`.
- Tests présents : `backend/tests/api/test_map_tiles.py`, `backend/tests/database/test_map_tile_cache.py`, `mobile/test/features/map/`.

La présence des tests ne confirme ni leurs résultats à cette révision ni la synchronisation visuelle réelle sur Android/iOS. Vérifier séparément un signalement avant/après expiration sur le serveur et son délai d'effacement sur téléphone ; noter les deux horodatages.