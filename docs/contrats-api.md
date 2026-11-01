# Contrats HTTP NoWave

Base publique : `https://api.no-wave.fr`. JSON par défaut, sauf photos et tuiles.
En local, `/docs` expose l'OpenAPI ; il est désactivé en production.

## Conventions et accès

- `Token` : `Authorization: Bearer <ID token Firebase>` valide.
- `Profil` : Token + e-mail vérifié + profil NoWave actif.
- `Admin` : Profil + rôle `admin`. Les inscriptions créent un rôle `user`.
- `Public` : aucun token. Les routes marines publiques ne reçoivent pas le token.
- Les identifiants sont des UUID. Les dates/instants sont ISO 8601 ; envoyer les
  instants avec fuseau, par exemple `2026-11-01T10:00:00Z`.
- `Point` = `{"type":"Point","coordinates":[5.37,43.29]}` : longitude puis latitude,
  bornées à ±180° et ±90°. Les nombres doivent être finis.
- Dans les modèles ci-dessous, `?` signifie nullable. Les champs d'entrée indiqués
  facultatifs peuvent être omis. Les requêtes JSON de profil, bateau, appareil,
  position, signalement et modération refusent les champs inconnus.

### Erreurs

Les erreurs JSON de l'API suivent cette enveloppe :

```json
{"error":{"code":"user_not_found","message":"user profile not found","details":null}}
```

| HTTP | Codes usuels |
| --- | --- |
| 401 | `authentication_required`, `invalid_authentication_token` |
| 403 | `email_not_verified`, `user_inactive`, `admin_required` |
| 404 | Ressource absente : `user_not_found`, `boat_not_found`, `report_not_found`, `device_not_found`, `photo_not_found` |
| 409 | Conflit métier ; codes précisés par ressource ci-dessous |
| 422 | `request_validation_error`, avec `details: [{loc, msg, type}]`, ou validation métier |
| 503 | `dependency_unavailable`, `photo_storage_unavailable`, `http_503` pour les sources marines |

Le proxy peut répondre 429 sur limitation de débit ou 413 sur corps trop gros.
Ne pas supposer que ces réponses du proxy sont du JSON.

## Santé et version

| Méthode et chemin | Accès | Réponse |
| --- | --- | --- |
| `GET /health` | Public | 200 `{"status":"ok"}` |
| `GET /health/ready` | Public | 200 `{"status":"ready","database":"ok"}` ; 503 `{"status":"not_ready","database":"unavailable"}` |
| `GET /version` | Public | 200 `{"service":"nowave-api","version":"<révision>"}` |

La readiness vérifie la connexion SQL.

## Profil

| Méthode et chemin | Accès | Entrée → sortie |
| --- | --- | --- |
| `POST /api/v1/users/me` | Token + e-mail vérifié | `{"username":"Marin"}` → 201 `UserProfile` |
| `GET /api/v1/users/me` | Token | Sans body → 200 `UserProfile` ; 404 si absent |
| `PATCH /api/v1/users/me` | Profil | Champs à modifier → 200 `UserProfile` |
| `DELETE /api/v1/users/me` | Token | Sans body → 204, sans contenu |

`username` : 1–100 caractères, espaces de bord retirés, unique.
Le PATCH accepte `username`, `date_of_birth` (date `YYYY-MM-DD` ou null),
`nationality` (deux lettres ou null), `show_user_name`, `show_boat_info` et
`notifications_enabled` (booléens). Un champ omis reste inchangé ; seuls date
et nationalité acceptent null. Les trois préférences sont fausses à la création.
Les codes pays sont normalisés en majuscules.

Exemple `UserProfile` :

```json
{
  "id":"11111111-1111-4111-8111-111111111111",
  "username":"Marin","date_of_birth":null,"nationality":"FR",
  "role":"user","status":"active",
  "show_user_name":false,"show_boat_info":false,"notifications_enabled":false,
  "created_at":"2026-11-01T10:00:00Z","updated_at":"2026-11-01T10:00:00Z"
}
```

`role` vaut `user|admin`, `status` vaut `active|suspended`. L'e-mail et le mot de
passe ne se modifient pas par ce PATCH. GET ne crée pas le profil.
Conflits 409 : `user_already_exists`, `username_already_exists`,
`email_already_registered`. Ce dernier ne signifie pas que l'UID courant a un profil.
La suppression efface aussi l'identité Firebase ; elle peut être répétée après
une suppression SQL réussie dont l'étape Firebase a échoué.

## Bateau

Toutes les routes exigent Profil. Un seul bateau par utilisateur.

| Méthode et chemin | Entrée → sortie |
| --- | --- |
| `POST /api/v1/users/me/boat` | `boat_type` requis ; `name`, `flag_country` facultatifs → 201 `Boat` |
| `GET /api/v1/users/me/boat` | Sans body → 200 `Boat` |
| `PATCH /api/v1/users/me/boat` | Champs à modifier → 200 `Boat` |
| `DELETE /api/v1/users/me/boat` | Sans body → 204 |

`boat_type` : `voilier|bateau_moteur|catamaran|semi_rigide|jet_ski|autre`.
`name` : chaîne de 100 caractères maximum ou null ; vide devient null.
`flag_country` : deux lettres normalisées en majuscules ou null.
Le PATCH accepte ces trois champs ; `boat_type` ne peut pas être null.
`Boat` = `id: UUID`, `name: string?`, `boat_type`, `flag_country: string?`,
`created_at: datetime`, `updated_at: datetime`.
Erreurs : 404 `boat_not_found`, 409 `boat_already_exists`.

## Appareil et position GPS

| Méthode et chemin | Accès | Entrée → sortie |
| --- | --- | --- |
| `PUT /api/v1/devices/current` | Profil | `installation_id: UUID`, `platform: android\|ios`, `fcm_token: string?` facultatif → 200 `Device` |
| `PUT /api/v1/devices/current/position` | Profil | Header `X-Installation-ID: <UUID>` + mesure JSON → 200 `DevicePosition` |
| `DELETE /api/v1/devices/current` | Token | Même header, sans body → 204 |

`Device` = `id: UUID`, `installation_id: UUID`, `platform`, `is_active: bool`,
`last_seen_at: datetime`. Le token FCM peut être null ; une chaîne vide est refusée.
Un appareil enregistré doit appartenir au compte courant ; conflit :
409 `device_conflict`. Un appareil introuvable donne 404 `device_not_found`.

Mesure requise : `position: Point`, `accuracy_m: number` entre 0 et 50,
`measured_at: datetime` avec fuseau ; `heading_deg: number?` est facultatif,
entre 0 inclus et 360 exclu.
`DevicePosition` reprend ces champs et ajoute `received_at: datetime`.
Le serveur conserve la mesure la plus récente. Erreurs :
422 `gps_precision_insufficient`, 422 `device_position_future` au-delà de cinq
minutes dans le futur, 409 `device_position_stale` si la mesure est plus ancienne que celle stockée.

## Signalements

Toutes les routes exigent Profil. `category` vaut
`marine_animal|obstruction|pollution` ; `positioning_mode` vaut `manual|photo`.

| Méthode et chemin | Entrée → sortie |
| --- | --- |
| `POST /api/v1/reports` | Création ci-dessous → 201 `ReportCreated` ; 200 si rejeu identique |
| `GET /api/v1/reports/{report_id}` | Sans body → 200 `ReportDetail` ; 404 si absent, retiré ou expiré |
| `POST /api/v1/reports/{report_id}/photo` | Multipart `file` JPEG → 201 `PhotoMetadata` ; 200 si même fichier répété |

Création manuelle :

```json
{
  "client_report_id":"22222222-2222-4222-8222-222222222222",
  "category":"obstruction","positioning_mode":"manual",
  "description":"Objet flottant",
  "final_position":{"type":"Point","coordinates":[5.37,43.29]},
  "observed_at":"2026-11-01T10:00:00Z"
}
```

Envoyer une date d'observation non future et strictement plus récente que 24 h.
`expires_at = observed_at + 24 h`. `description` est facultative, nullable,
limitée à 250 caractères. `positioning_mode` vaut `manual` par défaut.
Pour `photo`, ajouter `positioning` au format de l'estimation ci-dessous ;
ce champ est interdit en mode manuel. `final_position` reste la position confirmée.
Réutiliser le même `client_report_id` et les mêmes données lors d'un réessai ;
un contenu différent donne 409 `report_client_id_conflict`.

`ReportCreated` : `id: UUID`, `author_id: UUID?`, `client_report_id: UUID`,
`category`, `positioning_mode`, `description: string?`, `final_position: Point`,
`observed_at`, `expires_at`, `created_at`, `updated_at` (datetime),
`status: active|expired|removed`, `version: int`, `photo: {status, url: string?}?`.
Le statut photo vaut `pending|uploaded|failed` ; la création ne fournit pas d'URL.

`ReportDetail` : `id`, `version`, `category`, `description`, `positioning_mode`,
`final_position`, `status`, `observed_at`, `expires_at`, puis :

- `author: {username: string?, deleted: bool}?`, selon la préférence de visibilité ;
- `boat: {name: string?, boat_type}?`, selon la préférence de visibilité ;
- `photo: {status: pending|uploaded|failed, url: string?}?`.

L'URL de lecture expire après cinq minutes. Une photo masquée ne reçoit pas de
nouvelle URL ; celles déjà émises restent valables jusqu'à expiration.

### Upload JPEG

Seul l'auteur d'un signalement photo peut envoyer son fichier :
`image/jpeg`, 1–500 000 octets, 1600 px maximum par côté, 2 560 000 pixels maximum,
sans EXIF. L'enveloppe multipart complète est limitée à 512 000 octets.

`PhotoMetadata` = `report_id: UUID`, `upload_status`, `size_bytes: int`, `mime_type: string`.
Erreurs : 403 `photo_upload_forbidden`, 404 `report_not_found`,
409 `photo_already_uploaded` si contenu différent, 422 `invalid_photo`,
503 `photo_storage_unavailable`. Un upload échoué laisse le signalement créé ;
réessayer sur le même identifiant.
Les validations de création peuvent aussi donner 422 `invalid_observed_at`,
`invalid_report_position`, `invalid_report_description` ou `invalid_positioning_input`.
Les routes de modification/suppression par l'auteur et `GET /api/v1/users/me/reports`
ne sont pas disponibles.

## Estimation de position par photo

`POST /api/v1/position-estimates` — Profil, JSON → 200 :
`{"estimated_position": Point|null, "estimated_distance_m": number|null}`.

| Champ d'entrée | Contrat |
| --- | --- |
| `observer_position` | Point requis |
| `gps_accuracy_m` | Nombre requis, 0–50 m |
| `azimuth_deg` | Nombre requis, 0 inclus à 360 exclu |
| `inclination_deg` | Nombre fini requis ; une visée hors de [-90, 0[ ou sans intersection donne deux résultats null |
| `camera_height_m` | Nombre requis, positif, ≤ 9999,99 m ; arrondi au centimètre, résultat ≥ 0,01 m |
| `captured_at` | Instant avec fuseau requis |
| `camera_height_source` | Chaîne facultative nullable, 30 caractères maximum |
| `camera_height_uncertainty_m` | Nombre facultatif nullable, ≥ 0 |
| `focal_length_mm`, `zoom_ratio` | Nombres facultatifs nullables, strictement positifs |

Erreurs : 422 `gps_precision_insufficient`, `invalid_positioning_input` ou
`request_validation_error`. L'estimation ne publie aucun signalement.

## Historique des alertes

`GET /api/v1/users/me/alerts` — Profil, query `page`, `limit` → 200 page d'`Alert`.

`Alert` = `id: UUID`, `report_id: UUID`, `report_version: int`, `category`,
`position: Point`, `distance_m: number`, `alerted_at: datetime`.
Les alertes sont triées de la plus récente à la plus ancienne. Cet historique
conserve l'instantané reçu, même si le signalement a expiré ou si le push a échoué.

Le push FCM contient `notification` (titre/texte) et `data` dont toutes les
valeurs sont des chaînes : `recipient_firebase_uid`, `notification_id`, `alert_id`,
`report_id`, `report_version`, `category`,
`distance_m`, `position_dms`, `position` (Point JSON), `alerted_at`, `expires_at`.
`alert_id` est commun aux appareils du même utilisateur ; le mobile déduplique
et vérifie l'expiration avant ouverture. `sent` signifie acceptation par FCM,
pas confirmation de réception sur le téléphone.

La pagination des alertes et listes admin accepte `page` de 1 à 1 000 000
(défaut 1), `limit` de 1 à 100 (défaut 20). `total` compte tous les résultats,
`pages` leur nombre de pages ; une page hors fin donne `items: []`.

```json
{"items":[],"page":1,"limit":20,"total":0,"pages":0}
```

## Carte des observations

| Méthode et chemin | Accès | Contrat |
| --- | --- | --- |
| `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` | Profil | MVT, couche `reports` ; Z0–22 ; filtres `category`, `report_id: UUID` facultatifs |
| `GET /api/v1/map/observations` | Public | JSON paginé par curseur, paramètres ci-dessous |
| `GET /api/v1/map/web-config` | Public | 200 `{"mapbox_token":"pk.…"}` ; chaîne vide si absent ou invalide |

Les MVT ne contiennent que les signalements actifs non expirés :
`report_id`, `category`, `cluster: bool`, `cluster_count: int`.
Sous Z9, les groupes peuvent omettre identifiant et catégorie ; le filtre
`report_id` désactive le regroupement. Cache privé 15 s, `Vary: Authorization`.
Les réponses publiques `observations` et `web-config` utilisent `no-store`.

Query des observations : `category` facultatif, `q` ≤ 120 caractères,
`limit` 1–500 (défaut 200), `cursor` facultatif ≤ 160 caractères. L'emprise
`west/south/east/north` se donne en entier ou s'omet ; `south < north`,
`west != east`. `west > east` traverse l'antiméridien. Garder les mêmes filtres
avec le `next_cursor` reçu. Emprise incomplète/incohérente ou curseur illisible :
422 `http_422` ; paramètre hors bornes : 422 `request_validation_error`.

Réponse : `{items: [PublicObservation], has_more: bool, next_cursor?: string}`.
`PublicObservation` = `id: UUID`, `category`, `longitude: number`, `latitude: number`,
`observed_at`, `expires_at`, `description?: string`, `author_username?: string`.
Les valeurs nulles sont omises. Tri : observation puis UUID décroissants.
Le pseudo respecte le consentement ; e-mail, bateau et photo restent privés.

## Couches marines publiques

Les routes XYZ FastAPI vérifient `0 ≤ x,y < 2^z` ; coordonnées invalides : 422.
GEBCO est statique : une tuile absente ou hors pyramide renvoie 404.

| Méthode et chemin | Bornes et format |
| --- | --- |
| `GET /api/v1/map/marine-features/{family}/{z}/{x}/{y}.geojson` | GeoJSON `FeatureCollection`, WGS84 ; familles et zooms ci-dessous |
| `GET /api/v1/map/seamarks/{z}/{x}/{y}.pbf` | Z0–14, couche `seamark` |
| `GET /api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf` | Z0–14, couches `port_infrastructure`, `water_polygons`, `pier_lines`, `pier_polygons` |
| `GET /api/v1/map/harbours/{z}/{x}/{y}.pbf` | Z0–14, couche `harbour` |
| `GET /api/v1/map/depth-contours/{z}/{x}/{y}.pbf` | Z0–16, couche `depth_contour` |
| `GET /api/v1/map/soundings/{z}/{x}/{y}.pbf` | Z0–16, couche `sounding` |
| `GET /api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf` | Z0–16, couche `underwater_hazard` |
| `GET /api/v1/map/bathymetry/{z}/{x}/{y}.png` | Z0–14, PNG visuel ; hors couverture : PNG transparent 200 |
| `GET /api/v1/map/marine-sources` | 200 `{usage: string, sources: [...]}` ; chaque source décrit identité, familles, produit, crédit, licence, liens et limites |
| `GET /api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp` | Z0–6, WebP statique servi par Nginx, cache un an ; absent de FastAPI seul |

Snapshots autorisés : `harbours` Z6–14, `seamarks` Z10–14,
`underwater-hazards` Z10–14, `depth-contours` Z12 uniquement, `soundings` Z10–16.
Les courbes, sondes et dangers restent vides sous Z12 ; marques sous Z10,
ports sous Z6. Chaque snapshot est borné à 6 000 objets et 4 Mio.

Les objets portent une géométrie, une identité et leurs propriétés source ;
les propriétés de profondeur distinguent unités, datum et nature modélisée.
Les fournisseurs et leurs licences sont décrits dans [sources et licences](architecture/sources-et-licences.md).
MVT : `application/vnd.mapbox-vector-tile`. GeoJSON : `application/geo+json`.
`X-NoWave-Marine-Status` distingue `ok`, `degraded`, `unavailable` et, pour les
sondes, `empty`, `outside-coverage`, `below-minzoom`.

Cache vectoriel public 300 s, 15 s si dégradé ; sondes toujours `no-store`.
Raster régional : 24 h, sauf rendu partiel `no-store`.
Panne totale : 503, `no-store`, `Retry-After: 15`, sans faux succès vide.
Une requête de sondes, snapshot ou raster annulée peut finir en 499.
Ces données sont destinées à l'affichage, pas à la navigation.

## Administration REST

Toutes ces routes exigent Admin, via le token Bearer, sans cookie web.

| Méthode et chemin | Entrée → sortie |
| --- | --- |
| `GET /api/v1/admin/reports` | `page`, `limit`, `status: active\|expired\|removed` facultatif → 200 page d'`AdminReportSummary` |
| `GET /api/v1/admin/reports/{report_id}` | Sans body → 200 `AdminReportDetail`, même retiré ou expiré |
| `GET /api/v1/admin/users` | `page`, `limit`, `status: active\|suspended` facultatif → 200 page d'`AdminUser` |
| `GET /api/v1/admin/moderation-actions` | `page`, `limit` → 200 page de `ModerationAction` |
| `DELETE /api/v1/admin/reports/{report_id}` | `{"reason":"Doublon"}` → 204 |
| `PATCH /api/v1/admin/reports/{report_id}` | `{"status":"active","reason":"Retrait corrigé"}` → 200 `ReportDetail` |
| `PATCH /api/v1/admin/reports/{report_id}/photo` | `{"hidden":true,"reason":"Photo inadaptée"}` → 200 `PhotoMetadata` |
| `PATCH /api/v1/admin/users/{user_id}` | `{"status":"suspended","reason":"Abus"}` ou `status: active` → 200 `UserProfile` |

Chaque motif doit être non vide après retrait des espaces. État déjà appliqué,
restauration impossible ou auto-suspension : 409 `moderation_conflict`.
Une ressource absente donne 404. Restaurer conserve l'expiration initiale :
un ancien signalement peut rester `expired` et aucune nouvelle alerte n'est créée.

| Modèle | Champs |
| --- | --- |
| `AdminReportSummary` | `id: UUID`, `category`, `positioning_mode`, `status`, `observed_at`, `expires_at`, `removed_at: datetime?`, `version: int`, `author_id: UUID?`, `author_username: string?`, `photo_status?`, `photo_hidden_at: datetime?`, `description: string?` |
| `AdminReportDetail` | `ReportDetail` + `removed_at: datetime?` ; auteur remplacé par `{id: UUID?, username: string?, email: string?, status?, deleted: bool}` ; photo ajoute `hidden_at: datetime?` |
| `AdminUser` | `id: UUID`, `username: string`, `email: string`, `role`, `status`, `created_at`, `updated_at`, `reports_count: int` |
| `ModerationAction` | `id: UUID`, `action`, `admin_user_id: UUID?`, `admin_username: string?`, `target_user_id: UUID?`, `target_report_id: UUID?`, `target_photo_report_id: UUID?`, `reason: string`, `previous_status: string?`, `new_status: string?`, `created_at` |

Les actions valent `remove_report|restore_report|hide_photo|suspend_user|reactivate_user`.
Les lectures admin ignorent les préférences de visibilité de l'auteur ; une photo
masquée reste sans URL, y compris en admin. L'audit est en lecture seule.

## Lectures JSON de la session web

Ces routes utilisent le cookie de connexion `/admin/login`, pas le Bearer.
Elles répondent `no-store` : session absente/invalide → 303 vers la connexion ;
accès refusé → 403 HTML ; dépendance indisponible → 503 HTML.

| Méthode et chemin | Query → réponse 200 |
| --- | --- |
| `GET /admin/data/reports` | Quatre bornes requises, `west < east`, `south < north` → GeoJSON de 1 000 points maximum, propriétés `{id, category, status}`, booléen `truncated` |
| `GET /admin/data/reports/{target_id}` | Sans query → `AdminReportDetail` |
| `GET /admin/data/users` | `page`, `status` facultatif, `search` ≤ 80 caractères → `{items: [AdminUser], page, pages, total}`, 20 éléments par page |
| `GET /admin/data/users/{user_id}/reports` | `page` → `{items: [{id, category, status, observed_at}], page, has_more}`, 20 éléments par page |

`page` conserve la borne 1–1 000 000. Recherche utilisateur : pseudo/e-mail
partiel ou UUID exact. Les erreurs locales utilisent `{error: string}` pour
emprise/statut invalides (422) ou détail absent (404). Les autres paramètres
invalides suivent la validation 422. La configuration de session est dans le [README admin](../backend/app/web/README.md).
