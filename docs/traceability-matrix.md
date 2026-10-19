# Matrice de traçabilité — NoWave MVP

**Référence technique :** branche `dev`, commit [`6b54aa861e5cda93bf9b573c443f5946d230945d`](https://github.com/FBCIFY/NoWave/commit/6b54aa861e5cda93bf9b573c443f5946d230945d), constat du 19 octobre 2026. **Référence fonctionnelle :** [documentation technique NoWave](https://docs.google.com/document/d/1PbbCySYhRy8_aeU4T19nfPSq3dXU-QI9/edit). Suivi : [Linear NoWave](https://linear.app/blueway).

**Lecture des preuves :** « Code identifié » signifie uniquement que la source existe au SHA indiqué. « Test présent » signifie qu'un fichier est dans Git, **pas** qu'il a été exécuté ici. « Rapport référencé » signifie qu'une preuve existe, sans réexécution ou vérification du matériel. La validation Android/iOS réelle et la recette VPS sont **non vérifiées dans ce correctif**, sauf preuve spécifique ultérieure.

| Parcours / capacité | Linear associé | Sources backend / mobile / infra | Tests / documents existants | Niveau de preuve à cette passe |
| --- | --- | --- | --- | --- |
| Inscription et profil | NW-51, NW-153, NW-155 | `backend/app/api/routes/users.py` ; `mobile/lib/features/auth/` ; `mobile/lib/features/profile/` | `backend/tests/api/test_users.py` ; `mobile/test/features/profile/` | Code identifié ; tests présents ; essai sur appareil non vérifié |
| Préférences et installations | NW-116, NW-117 | `backend/app/api/routes/devices.py` ; `backend/app/api/routes/users.py` ; `mobile/lib/features/profile/` | `backend/tests/api/test_devices.py` ; `backend/tests/api/test_my_alerts.py` | Code identifié ; tests présents ; autorisations OS réelles non vérifiées |
| Carte et tuiles mondiales MVT | NW-111, NW-114 | `backend/app/api/routes/map_tiles.py` ; `backend/app/application/services/map_query.py` ; `mobile/lib/features/map/` | `backend/tests/api/test_map_tiles.py` ; `backend/tests/database/test_map_tile_cache.py` ; `mobile/test/features/map/` | Code identifié ; tests présents ; cache/délai visuel en condition réelle non vérifiés |
| Publication manuelle | NW-104 | `backend/app/api/routes/reports.py` ; `backend/app/application/services/create_report.py` ; `mobile/lib/features/reports/` | `backend/tests/api/test_reports.py` ; `mobile/test/features/reports/` | Code identifié ; tests présents ; publication sur téléphone réel non vérifiée |
| Estimation photo et upload | NW-109, NW-112 | `backend/app/api/routes/position_estimates.py` ; `backend/app/api/routes/reports.py` ; `mobile/lib/features/camera/` | `backend/tests/api/test_photo_uploads.py` ; `backend/tests/api/test_position_estimates.py` ; `mobile/test/features/camera/` | Code identifié ; tests présents ; stockage externe réel non vérifié |
| Historique d'alertes | NW-125 | `backend/app/api/routes/users.py` ; `backend/app/application/services/list_my_alerts.py` ; `mobile/lib/features/alerts/` | `backend/tests/api/test_my_alerts.py` ; `mobile/test/features/alerts/` | Code identifié ; tests présents ; restitution réelle non vérifiée |
| Alertes FCM et navigation carte | NW-157, NW-163 | `backend/app/application/services/send_notifications.py` ; `mobile/lib/core/notifications/` ; `mobile/lib/features/alerts/` | `backend/tests/database/test_notification_worker.py` ; `mobile/test/features/alerts/` ; [rapport NW-163](test-reports/NW-163.md) | Rapport de tests automatisés disponible ; FCM/APNs et rendu réel non validés dans ce correctif |
| Administration / modération | NW-48 (données), tickets de modération selon Linear | `backend/app/api/routes/admin.py` ; `backend/app/web/routes/admin_pages.py` ; `backend/app/application/services/moderation.py` | `backend/tests/api/test_admin_moderation.py` ; `backend/tests/api/test_admin_web.py` | Code identifié ; tests présents ; sécurité/recette du back-office non vérifiées ici |
| Sauvegarde et déploiement VPS | NW-57, NW-84 | `.github/workflows/checks.yml` ; `.github/workflows/production.yml` ; `deploy/hostinger/` | [guide de déploiement](../deploy/README.md) ; [tests CI](TESTING.md) | Workflow lu ; nouvelle livraison et restauration non exécutées ici |
| Documentation et traçabilité | NW-83, NW-129 | `README.md` ; `docs/README.md` ; `docs/parcours/` ; ce fichier | Revue documentaire CON-024/025/026/027/039 | Structure documentaire préparée ; confirmation finale lors de la revue PR |

## Exclusions explicites du MVP connecté au SHA de référence

| Fonction demandée | Ticket | État observé |
| --- | --- | --- |
| `PATCH /api/v1/reports/{report_id}` / modification par l'auteur | NW-73 | Route absente dans le code ; ne pas annoncer comme disponible |
| `DELETE /api/v1/reports/{report_id}` / retrait par l'auteur | NW-73 | Route absente dans le code ; ne pas confondre avec `DELETE /api/v1/admin/reports/{report_id}` |
| `GET /api/v1/users/me/reports` / historique des signalements créés | NW-74 | Route absente ; l'historique `/users/me/alerts` concerne **les alertes** |
| Regroupement métier de signalements à 200 m | NW-75 | Ne pas confondre avec le clustering des MVT en fonction du zoom ; vérifier le comportement réel avant toute revendication |

## Modèle de preuve pour une recette nouvelle

Pour chaque essai, ajouter **date et fuseau**, **SHA**, **ticket**, **environnement / appareil et version OS**, **commande ou actions**, **résultat réel**, **lien vers journal / capture autorisée**, **limites** et **responsable**. Ne pas déclarer « testé » une fonctionnalité uniquement parce que le ticket est `Done`.

Les décisions documentaires validées le 19/10/2026 sont : CON-024/A (cache inchangé), CON-025/C (API réelles seulement), CON-026/A (déploiement actuel depuis `dev`), CON-027/A (ancienne BDD archivée), CON-039/C (README, parcours et preuves séparées). Aucun changement applicatif ni migration n'est demandé par ce lot.