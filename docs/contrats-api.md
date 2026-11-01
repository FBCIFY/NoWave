# Contrats API

Base publique : `https://api.no-wave.fr`. En local, l’API écoute par défaut sur `http://127.0.0.1:8000` ; `/docs` donne les schémas OpenAPI en développement.

Envoyer l’ID token Firebase sur les routes utilisateur :

```http
Authorization: Bearer <ID_TOKEN>
```

Il faut un e-mail vérifié et un profil actif, sauf indication contraire. Le rôle vaut `user` à l’inscription ; les routes admin exigent `admin`. Les routes publiques n’ont pas besoin de token. Sous `/admin/data`, le navigateur utilise sa session.

Les requêtes envoient du JSON, sauf la photo en multipart. Utiliser des UUID, des dates ISO 8601 avec fuseau et des nombres finis.
Un point GeoJSON s’écrit `{"type":"Point","coordinates":[5.37,43.29]}` : longitude puis latitude, bornées à ±180° et ±90°.

## Profil et bateau

- `POST /api/v1/users/me` — `{"username":"Marin"}`, token et e-mail vérifié. Renvoie le profil, 201.
- `GET /api/v1/users/me` — token seul. Renvoie le profil, 200 ; 404 s’il n’existe pas.
- `PATCH /api/v1/users/me` — champs à modifier. Renvoie le profil, 200.
- `DELETE /api/v1/users/me` — token seul, sans body. Supprime aussi l’identité Firebase, 204.

Le pseudo est unique, de 1 à 100 caractères ; les espaces de bord sont retirés. Le PATCH profil accepte :

- `username`, `date_of_birth` au format `YYYY-MM-DD`, `nationality` sur deux lettres ;
- `show_user_name`, `show_boat_info`, `notifications_enabled` : booléens, faux à la création.

Un champ omis reste inchangé. Seules la date de naissance et la nationalité acceptent `null`.
GET ne crée pas le profil. Après un POST dont la réponse a été perdue, `user_already_exists` permet de reprendre avec GET. Les deux autres conflits 409 sont `username_already_exists` et `email_already_registered` ; ce dernier ne prouve pas qu’un profil existe pour l’UID connecté. Une suppression interrompue peut être répétée.

- `POST /api/v1/users/me/boat` — `boat_type` requis ; `name` et `flag_country` facultatifs. Renvoie le bateau, 201.
- `GET /api/v1/users/me/boat` — renvoie le bateau, 200 ; 404 s’il n’existe pas.
- `PATCH /api/v1/users/me/boat` — champs à modifier. Renvoie le bateau, 200.
- `DELETE /api/v1/users/me/boat` — sans body, 204.

Un seul bateau par compte. Types : `voilier|bateau_moteur|catamaran|semi_rigide|jet_ski|autre`.
`name` accepte 100 caractères maximum ou null ; `flag_country` accepte deux lettres ou null. Le PATCH préserve les champs omis et refuse un type null. Un bateau déjà présent donne 409 `boat_already_exists`.

## Appareil et GPS

- `PUT /api/v1/devices/current` — `installation_id: UUID`, `platform: android|ios`, `fcm_token` facultatif ou `null`. Renvoie l’appareil, 200.
- `PUT /api/v1/devices/current/position` — header `X-Installation-ID: <UUID>` et mesure ci-dessous. Renvoie la mesure enregistrée, 200.
- `DELETE /api/v1/devices/current` — token seul et même header, sans body, 204.

La mesure contient `position` (point), `accuracy_m` de 0 à 50 m et `measured_at` avec fuseau.
`heading_deg` est facultatif : de 0 inclus à 360 exclu, ou null.
Une mesure plus ancienne que celle stockée donne 409 `device_position_stale` ; plus de cinq minutes d’avance donne 422 `device_position_future`. Un conflit d’installation ou de token FCM donne 409 `device_conflict`.

## Signalements et photos

- `POST /api/v1/reports` — body ci-dessous. Renvoie le signalement, 201 ; 200 si la même création est rejouée.
- `GET /api/v1/reports/{report_id}` — détail, 200 ; 404 si absent, retiré ou expiré.
- `POST /api/v1/reports/{report_id}/photo` — multipart `file` de type `image/jpeg`, réservé à l’auteur d’un signalement photo. Renvoie les métadonnées, 201 ; 200 pour le même JPEG répété.

Champs de création :

- `client_report_id: UUID`, `category: marine_animal|obstruction|pollution`, `final_position` (point confirmé), `observed_at` ;
- `description` facultative ou null, 250 caractères maximum ; `positioning_mode` vaut `manual` par défaut ou `photo` ;
- en mode photo, `positioning` reprend les mesures de capture décrites ci-dessous ; ce champ est interdit en mode manuel.

L’observation doit être non future et dater de moins de 24 h. Elle expire à `observed_at + 24 h`.
Lors d’un réessai, garder le même `client_report_id` et les mêmes données ; un contenu différent donne 409 `report_client_id_conflict`.

L’upload est séparé de la création : son échec conserve le signalement et le réessai utilise le même identifiant.
Le JPEG doit faire de 1 à 500 000 octets, 1600 px maximum par côté et 2 560 000 pixels au total, sans EXIF. L’enveloppe multipart est limitée à 512 000 octets.
Erreurs d’upload : 403 `photo_upload_forbidden`, 409 `photo_already_uploaded`, 422 `invalid_photo`, 503 `photo_storage_unavailable`.
L’URL photo du détail expire après cinq minutes. Masquer la photo bloque les nouvelles URL ; celles déjà émises expirent normalement.

## Estimation de position

`POST /api/v1/position-estimates` renvoie 200 avec `estimated_position` (point) et `estimated_distance_m`.
Champs requis : `observer_position`, `gps_accuracy_m` de 0 à 50 m, `azimuth_deg` de 0 inclus à 360 exclu, `inclination_deg`, `camera_height_m` et `captured_at` avec fuseau.
La hauteur est positive, au plus 9999,99 m ; arrondie au centimètre, elle doit rester au moins égale à 0,01 m.
Champs facultatifs nullables : `camera_height_source` (30 caractères maximum), `camera_height_uncertainty_m` ≥ 0, `focal_length_mm` et `zoom_ratio` strictement positifs.
Une visée hors de [-90, 0[ ou sans intersection renvoie les deux résultats à null. L’estimation ne publie rien.

## Alertes

`GET /api/v1/users/me/alerts?page=1&limit=20` renvoie 200 avec l’historique paginé des alertes reçues, de la plus récente à la plus ancienne.
FCM transmet le titre et le texte dans `notification`, puis des chaînes dans `data` : `recipient_firebase_uid`, `notification_id`, `alert_id`, `report_id`, `report_version`, `category`, `distance_m`, `position_dms`, `position`, `alerted_at`, `expires_at`. L’app vérifie le compte et l’expiration, puis déduplique avec `alert_id`. `sent` signifie acceptation par FCM, sans confirmation de réception.

Le choix des destinataires et les réessais sont décrits dans [signalements et alertes](signalements-et-alertes.md#recevoir-une-alerte).

## Carte

- `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` — profil actif. Z0–22, couche `reports`, filtres `category` et `report_id` facultatifs.
- `GET /api/v1/map/observations` — public. Observations actives paginées par curseur.
- `GET /api/v1/map/web-config` — public. `mapbox_token`, chaîne vide si absent ou invalide.

Les routes marines sont publiques :

- `GET /api/v1/map/marine-features/{family}/{z}/{x}/{y}.geojson` — GeoJSON WGS84, familles ci-dessous.
- `GET /api/v1/map/seamarks/{z}/{x}/{y}.pbf` — Z0–14, couche `seamark`.
- `GET /api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf` — Z0–14, couches `port_infrastructure`, `water_polygons`, `pier_lines`, `pier_polygons`.
- `GET /api/v1/map/harbours/{z}/{x}/{y}.pbf` — Z0–14, couche `harbour`.
- `GET /api/v1/map/depth-contours/{z}/{x}/{y}.pbf` — Z0–16, couche `depth_contour`.
- `GET /api/v1/map/soundings/{z}/{x}/{y}.pbf` — Z0–16, couche `sounding`.
- `GET /api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf` — Z0–16, couche `underwater_hazard`.
- `GET /api/v1/map/bathymetry/{z}/{x}/{y}.png` — Z0–14, raster régional.
- `GET /api/v1/map/marine-sources` — crédits, licences, sources et limites.
- `GET /api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp` — Z0–6, fond statique servi par Nginx, absent de FastAPI seul.

Pour les observations publiques : `category`, `q` ≤ 120 caractères, `limit` de 1 à 500 (200 par défaut), `cursor`.
Donner les quatre bornes `west/south/east/north` ou aucune, avec `south < north` et `west != east`. `west > east` traverse l’antiméridien.
La réponse contient `items`, `has_more` et éventuellement `next_cursor` ; garder les mêmes filtres pour la suite. E-mail, bateau et photo restent privés, le pseudo suit la préférence de visibilité.

Les MVT des signalements contiennent `report_id`, `category`, `cluster`, `cluster_count`. Les points sont regroupés sous Z9 ; le filtre `report_id` désactive le regroupement. Seuls les signalements actifs non expirés sont inclus.
Les snapshots acceptent `harbours` Z6–14, `seamarks` et `underwater-hazards` Z10–14, `depth-contours` Z12 seulement, `soundings` Z10–16. Courbes, sondes et dangers restent vides sous Z12. Limite : 6 000 objets et 4 Mio par snapshot.
Les XYZ FastAPI vérifient `0 ≤ x,y < 2^z`, sinon 422. Une tuile GEBCO absente ou hors pyramide renvoie 404 ; une bathymétrie hors couverture renvoie un PNG transparent valide.

Caches HTTP : MVT des signalements privé 15 s ; GeoJSON/MVT marins public 300 s, 15 s si dégradés ; sondes, observations publiques et configuration web toujours `no-store`.
Raster régional : 24 h, sauf rendu partiel `no-store` ; GEBCO : un an. Une panne marine totale renvoie 503, `no-store`, `Retry-After: 15`. `X-NoWave-Marine-Status` indique notamment `ok`, `degraded` ou `unavailable`.

## Administration

Ces routes REST demandent un admin actif avec e-mail vérifié.

- `GET /api/v1/admin/reports` — `page`, `limit`, filtre `status: active|expired|removed`. Liste paginée, 200.
- `GET /api/v1/admin/reports/{report_id}` — détail, y compris retiré ou expiré, 200.
- `GET /api/v1/admin/users` — `page`, `limit`, filtre `status: active|suspended`. Liste paginée, 200.
- `GET /api/v1/admin/moderation-actions` — `page`, `limit`. Audit paginé en lecture seule, 200.
- `DELETE /api/v1/admin/reports/{report_id}` — `{"reason":"Doublon"}`, 204.
- `PATCH /api/v1/admin/reports/{report_id}` — `{"status":"active","reason":"Retrait corrigé"}`. Détail, 200.
- `PATCH /api/v1/admin/reports/{report_id}/photo` — `{"hidden":true,"reason":"Photo inadaptée"}`. Métadonnées photo, 200.
- `PATCH /api/v1/admin/users/{user_id}` — `{"status":"suspended","reason":"Abus"}`, ou statut `active`. Profil, 200.

Le motif doit être non vide après retrait des espaces. Une ressource absente donne 404 ; un état déjà appliqué, une restauration impossible ou l’auto-suspension donnent 409 `moderation_conflict`.
Restaurer conserve l’expiration initiale et ne crée aucune alerte. Les lectures admin ignorent les préférences de visibilité ; une photo masquée reste sans URL.

Les lectures du navigateur utilisent le cookie obtenu via `/admin/login`, avec `no-store`. Les formulaires POST exigent un jeton CSRF.
Session absente/invalide : 303 vers la connexion ; refus : 403 HTML ; dépendance indisponible : 503 HTML.

- `GET /admin/data/reports` — quatre bornes requises, `west < east`, `south < north`. GeoJSON, 1 000 points maximum et booléen `truncated`, 200.
- `GET /admin/data/reports/{target_id}` — détail admin, 200.
- `GET /admin/data/users` — `page`, `status`, `search` ≤ 80 caractères. `items`, `page`, `pages`, `total`, par 20, 200.
- `GET /admin/data/users/{user_id}/reports` — `page`. `items`, `page`, `has_more`, par 20, 200.

## Réponses et erreurs

La pagination des alertes et listes REST admin utilise `page` de 1 à 1 000 000, `limit` de 1 à 100, par défaut 1 et 20. Hors fin : `{"items":[],"page":1,"limit":20,"total":0,"pages":0}`.
Les erreurs JSON REST suivent `{"error":{"code":"user_not_found","message":"user profile not found","details":null}}`. Les lectures de session peuvent renvoyer `{error: string}` pour leurs erreurs locales.
Codes usuels : 401 token absent/invalide ; 403 accès refusé ; 404 ressource absente ; 409 conflit ; 422 saisie ou mesure invalide ; 503 dépendance indisponible. `request_validation_error` détaille les champs dans `details` ; `gps_precision_insufficient` signale une précision supérieure à 50 m.
Le proxy peut répondre 429 sur quota ou 413 sur corps trop gros, sans JSON garanti.

Pour vérifier le service, sans token :

- `GET /health` — 200 si FastAPI répond.
- `GET /health/ready` — 200 si PostgreSQL répond, sinon 503.
- `GET /version` — 200 avec `service` et la révision `version`.
