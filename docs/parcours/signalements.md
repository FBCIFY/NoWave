# Parcours — Création manuelle et photo des signalements

**Référence :** `dev@6b54aa8` (19/10/2026). Tickets de référence : NW-104, NW-109, NW-112 ; correctif [FIX T14 / NW-167](https://linear.app/blueway/issue/NW-167).

## Création manuelle

1. Depuis la carte, l'utilisateur choisit une catégorie (`marine_animal`, `obstruction` ou `pollution`) et une position finale en coordonnées GeoJSON `[longitude, latitude]` ; la description est facultative.
2. Le mobile envoie `POST /api/v1/reports` avec le `client_report_id` UUID, `observed_at`, le mode et les autres données autorisées. Le jeton Firebase authentifie la demande.
3. Le backend vérifie les règles métier, enregistre la transaction et retourne le signalement. La réutilisation du même identifiant permet de traiter une réponse perdue sans créer de doublon si le contenu est identique.

## Création photo

1. La caméra capture des mesures de position, cap et inclinaison ; l'estimation utilise `POST /api/v1/position-estimates` puis l'utilisateur confirme ou corrige la position finale.
2. `POST /api/v1/reports` crée le signalement photo et ses métadonnées ; `POST /api/v1/reports/{report_id}/photo` envoie ensuite le JPEG validé à l'API.
3. L'API stocke le JPEG dans un bucket Scaleway privé. La consultation autorisée utilise des URL temporaires ; la suppression des objets orphelins relève du service serveur `photo-cleanup`.

## Limites et erreurs

- Le serveur impose la durée de validité de 24 heures sur la date d'observation et des contrôles sur les coordonnées. Une observation expirée ne produit pas de nouveau signalement actif.
- Un nouvel envoi JPEG dans le parcours ouvert utilise le même signalement. Il n'existe pas de promesse de reprise automatique après fermeture du parcours.
- **Non disponibles dans le MVP connecté `dev@6b54aa8` :** `PATCH /api/v1/reports/{report_id}` et `DELETE /api/v1/reports/{report_id}` par l'auteur (NW-73). Les opérations de modération administrateur sont distinctes.
- L'historique personnel des signalements (`GET /api/v1/users/me/reports`, NW-74) est également absent ; ne pas le présenter comme livré.

## Références et preuves

Code : `backend/app/api/routes/reports.py`, `backend/app/api/routes/position_estimates.py`, `backend/app/application/services/create_report.py`, `backend/app/application/services/upload_report_photo.py`, `mobile/lib/features/reports/`, `mobile/lib/features/camera/`.

Tests présents : `backend/tests/api/test_reports.py`, `backend/tests/api/test_photo_uploads.py`, `backend/tests/api/test_position_estimates.py`, `mobile/test/features/camera/`. Vérifier la validation de bout en bout du stockage, la taille/qualité JPEG et la publication sur appareil séparément.