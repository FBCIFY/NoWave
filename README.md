# NoWave

NoWave permet de signaler des obstacles, des animaux marins et de la pollution, puis de recevoir des alertes à proximité. L’app est en Flutter, l’API en FastAPI avec PostgreSQL/PostGIS. Firebase gère les comptes et les notifications ; Mapbox affiche la carte.

[Télécharger l’app mobile](https://no-wave.fr/downloads/mobile/).

Le responsable du projet attribue le rôle `admin` au compte de l’utilisateur désigné à sa création. L’[administration](https://no-wave.fr/admin) utilise ce même compte.

## Démarrer

Docker Compose suffit pour lancer le site, l’API et la base. Toutes les commandes de ce guide partent de la racine du dépôt.

```sh
test -f .env || cp .env.example .env
```

Compléter `.env` : mot de passe PostgreSQL, fichier de compte de service Firebase, clé web Firebase, jeton public Mapbox et accès au bucket privé Scaleway. Garder les secrets hors Git.

```sh
docker compose up --build -d --wait
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

`notifications` envoie les alertes ; `photo-cleanup` supprime les objets photo non référencés depuis au moins une heure.

Ouvrir `https://localhost:8443` et accepter le certificat local. L’admin est sous `/admin`, l’API sur le port 8000. Les ports se règlent dans `.env` ; les migrations s’appliquent au démarrage. `docker compose down` arrête les services en conservant les données.

## Développer

Prérequis : Python 3.12, Flutter 3.47.5 et Node.js 24. Préparer l’environnement Python pour l’API, l’aperçu web et les tests :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
set -a
. .env
set +a
```

### Backend

Pour lancer l’API sur le poste, arrêter la stack Docker et ne démarrer que la base :

```sh
docker compose down
docker compose up -d --wait database
export GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_FILE"
(cd backend && alembic -c alembic.ini upgrade head)
PYTHONPATH=backend python -m uvicorn app.main:app --host 127.0.0.1 --port "${NOWAVE_API_PORT:-8000}"
```

`DATABASE_URL` doit reprendre le mot de passe et le port de la base, `localhost:55432` par défaut. Les clés Scaleway et `FIREBASE_WEB_API_KEY` acceptent aussi une variable `_FILE` à la place de la valeur directe.

### Mobile

Créer la configuration locale :

```sh
test -f mobile/.env.json || cp mobile/.env.example.json mobile/.env.json
```

Compléter `mobile/.env.json` :

- `MAPBOX_ACCESS_TOKEN` : jeton public Mapbox.
- `API_BASE_URL` : backend NoWave, par exemple `https://api.no-wave.fr/`.
- `MARINE_API_BASE_URL` : backend marin facultatif ; vide, reprend l’API principale.

```sh
(cd mobile && flutter pub get --enforce-lockfile)
flutter devices
(cd mobile && flutter run -d <device-id> --dart-define-from-file=.env.json)
```

`<device-id>` vient de `flutter devices`. Firebase est déjà configuré dans les projets Android/iOS. Après une modification de `.env.json`, reconstruire et redémarrer l’app ; garder ce fichier hors Git.

L’API locale se joint à `http://10.0.2.2:8000/` sur émulateur Android et `http://127.0.0.1:8000/` sur simulateur iOS. Sur téléphone, utiliser l’API distante. En USB Android, `adb reverse tcp:8000 tcp:8000` permet aussi d’utiliser `http://127.0.0.1:8000/`. Ces adresses supposent le port API local 8000.

```sh
(cd mobile && flutter build apk --debug --dart-define-from-file=.env.json)
```

L’APK debug sert aux essais. La livraison Android/iOS demande une signature de plateforme. Caméra, GPS, notifications et reprise en arrière-plan se vérifient sur téléphone réel.

### Web

Cet aperçu remplace l’API locale : libérer le port 8000, puis lancer ce serveur avec l’environnement Python activé :

```sh
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

Dans un second terminal :

```sh
npm ci --prefix web
npm run dev --prefix web -- --port 5173
```

Ouvrir `http://127.0.0.1:5173/`. Le faux compte `admin@nowave.test` / `preview-only` sert uniquement à cet aperçu : données en mémoire et modération désactivée.

Le premier terminal lit `MAPBOX_PUBLIC_TOKEN` (jeton public `pk.*`) ou `NOWAVE_MAPBOX_CONFIG` (chemin du JSON contenant `MAPBOX_ACCESS_TOKEN`). Sans jeton, la carte reste indisponible.

`NOWAVE_API_URL`, dans le terminal Vite, change la destination du proxy ; défaut : `http://127.0.0.1:8000`.

```sh
npm run build --prefix web
```

Le site public et l’admin doivent utiliser les assets du même build. L’admin réel demande un e-mail Firebase vérifié, un profil actif de rôle `admin` et `FIREBASE_WEB_API_KEY` ou sa variante `_FILE`.

## API

Base publique : `https://api.no-wave.fr`. Les schémas complets et les réponses se consultent dans [l’OpenAPI locale](http://localhost:8000/docs), disponible en développement sur le port de l’API.

Envoyer `Authorization: Bearer <ID token Firebase>`. Sauf exception indiquée, les routes utilisateur exigent aussi un e-mail vérifié et un profil actif. Les routes admin ajoutent le rôle `admin` ; l’inscription crée un rôle `user`. Les routes publiques ne reçoivent pas le token.

Les corps sont en JSON, sauf l’upload photo. Identifiants UUID, instants ISO 8601 avec fuseau. Un point s’écrit `{"type":"Point","coordinates":[5.37,43.29]}` : longitude puis latitude, bornées à ±180° et ±90°. Les nombres doivent être finis.

### Compte et appareil

| Méthode et chemin | Entrée et résultat |
| --- | --- |
| `POST /api/v1/users/me` | `{"username":"Marin"}` ; token et e-mail vérifié → 201 profil |
| `GET /api/v1/users/me` | Token seul → 200 profil ; 404 s’il n’existe pas, sans création implicite |
| `PATCH /api/v1/users/me` | Champs à modifier → 200 profil |
| `DELETE /api/v1/users/me` | Token seul, sans body → 204 ; supprime aussi l’identité Firebase |
| `POST /api/v1/users/me/boat` | `boat_type` requis ; `name`, `flag_country` facultatifs → 201 bateau |
| `GET /api/v1/users/me/boat` | 200 bateau ; 404 si absent |
| `PATCH /api/v1/users/me/boat` | Champs à modifier → 200 bateau |
| `DELETE /api/v1/users/me/boat` | Sans body → 204 |
| `PUT /api/v1/devices/current` | `installation_id: UUID`, `platform: android\|ios`, `fcm_token` facultatif ou null → 200 appareil |
| `PUT /api/v1/devices/current/position` | Header `X-Installation-ID: <UUID>` et mesure GPS → 200 mesure enregistrée |
| `DELETE /api/v1/devices/current` | Token seul et même header, sans body → 204 |
| `GET /api/v1/users/me/alerts` | `page`, `limit` → 200 historique paginé des alertes reçues |

Le pseudo est unique, de 1 à 100 caractères après retrait des espaces de bord. Le PATCH profil accepte `username`, `date_of_birth`, `nationality`, `show_user_name`, `show_boat_info`, `notifications_enabled`. Un champ absent reste inchangé ; seuls date de naissance et nationalité acceptent null. La date de naissance suit `YYYY-MM-DD`, la nationalité a deux lettres ; les trois préférences sont fausses à la création.

Un seul bateau par compte : `boat_type` vaut `voilier|bateau_moteur|catamaran|semi_rigide|jet_ski|autre`, `name` a 100 caractères maximum ou null, `flag_country` a deux lettres ou null. Le PATCH conserve les champs absents et refuse un type null.

La mesure GPS contient `position` (point), `accuracy_m` de 0 à 50 m, `measured_at` avec fuseau et, facultativement, `heading_deg` entre 0 inclus et 360 exclu ou null. Une mesure plus ancienne que celle stockée donne 409 `device_position_stale` ; une avance de plus de cinq minutes donne 422 `device_position_future`.

Conflits 409 : `user_already_exists`, `username_already_exists`, `email_already_registered`, `boat_already_exists`, `device_conflict`. Après une réponse de création perdue, relire le profil seulement pour `user_already_exists` ; un conflit d’e-mail ne prouve pas que l’UID courant possède un profil. Une suppression de compte interrompue peut être répétée.

### Signalements et photos

| Méthode et chemin | Entrée et résultat |
| --- | --- |
| `POST /api/v1/reports` | Création ci-dessous → 201 signalement ; 200 si rejeu identique |
| `GET /api/v1/reports/{report_id}` | 200 détail ; 404 si absent, retiré ou expiré |
| `POST /api/v1/reports/{report_id}/photo` | Multipart `file`, `image/jpeg`, auteur du signalement photo uniquement → 201 métadonnées ; 200 si même JPEG répété |
| `POST /api/v1/position-estimates` | Mesures de capture ci-dessous → 200 estimation, sans publication |

Créer un signalement avec `client_report_id: UUID`, `category`, `final_position` (point confirmé) et `observed_at`. Catégories : `marine_animal|obstruction|pollution`. `description` est facultative ou null, limitée à 250 caractères. `positioning_mode` vaut `manual` par défaut ou `photo`.

L’observation doit être non future et strictement plus récente que 24 h ; `expires_at = observed_at + 24 h`. Réutiliser le même `client_report_id` et les mêmes données lors d’un réessai ; un contenu différent donne 409 `report_client_id_conflict`.

En mode `photo`, ajouter `positioning` avec les mesures de capture ; ce champ est interdit en mode manuel. L’upload reste séparé : son échec ne supprime pas le signalement, et le réessai utilise le même identifiant.

JPEG : 1 à 500 000 octets, 1600 px maximum par côté et 2 560 000 pixels au total, sans EXIF ; enveloppe multipart limitée à 512 000 octets. Erreurs : 403 `photo_upload_forbidden`, 409 `photo_already_uploaded`, 422 `invalid_photo`, 503 `photo_storage_unavailable`.

Le détail fournit l’URL photo signée, valable cinq minutes. Une photo masquée ne reçoit plus de nouvelle URL ; celles déjà émises expirent normalement.

L’estimation demande `observer_position` (point), `gps_accuracy_m` de 0 à 50 m, `azimuth_deg` de 0 inclus à 360 exclu, `inclination_deg`, `camera_height_m` positive jusqu’à 9999,99 m et `captured_at` avec fuseau. La hauteur est arrondie au centimètre et doit rester au moins égale à 0,01 m.

Mesures facultatives : `camera_height_source` (30 caractères maximum), `camera_height_uncertainty_m` ≥ 0, `focal_length_mm` et `zoom_ratio` strictement positifs ; toutes acceptent null. Une visée hors de [-90, 0[ ou sans intersection renvoie `estimated_position: null` et `estimated_distance_m: null` ; sinon la réponse contient le point estimé et la distance en mètres.

Les routes de modification/suppression par l’auteur et `GET /api/v1/users/me/reports` ne sont pas disponibles.

Les alertes concernent les autres comptes actifs ayant activé les notifications, avec un appareil actif dans un rayon de 10 NM (18 520 m) et une précision GPS de 50 m ou mieux.

Les pushs FCM contiennent un titre, un texte et des données en chaînes : `recipient_firebase_uid`, `notification_id`, `alert_id`, `report_id`, `report_version`, `category`, `distance_m`, `position_dms`, `position`, `alerted_at`, `expires_at`. L’app vérifie le compte destinataire et l’expiration, puis déduplique avec `alert_id`. `sent` signifie que FCM a accepté le message, pas que le téléphone l’a reçu.

### Carte

| Méthode et chemin | Accès et format |
| --- | --- |
| `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` | Profil actif ; Z0–22, couche `reports`, filtres facultatifs `category` et `report_id` |
| `GET /api/v1/map/observations` | Public ; observations actives paginées par curseur |
| `GET /api/v1/map/web-config` | Public ; `mapbox_token` public, chaîne vide si absent ou invalide |
| `GET /api/v1/map/marine-features/{family}/{z}/{x}/{y}.geojson` | Public ; GeoJSON WGS84, familles ci-dessous |
| `GET /api/v1/map/seamarks/{z}/{x}/{y}.pbf` | Public ; Z0–14, couche `seamark` |
| `GET /api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf` | Public ; Z0–14, couches `port_infrastructure`, `water_polygons`, `pier_lines`, `pier_polygons` |
| `GET /api/v1/map/harbours/{z}/{x}/{y}.pbf` | Public ; Z0–14, couche `harbour` |
| `GET /api/v1/map/depth-contours/{z}/{x}/{y}.pbf` | Public ; Z0–16, couche `depth_contour` |
| `GET /api/v1/map/soundings/{z}/{x}/{y}.pbf` | Public ; Z0–16, couche `sounding` |
| `GET /api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf` | Public ; Z0–16, couche `underwater_hazard` |
| `GET /api/v1/map/bathymetry/{z}/{x}/{y}.png` | Public ; Z0–14, raster visuel régional |
| `GET /api/v1/map/marine-sources` | Public ; crédits, licences, sources et limites |
| `GET /api/v1/map/seafloor/gebco-2026-v2/{z}/{x}/{y}.webp` | Public ; Z0–6, fond statique servi par Nginx, absent de FastAPI seul |

Snapshots GeoJSON autorisés : `harbours` Z6–14, `seamarks` et `underwater-hazards` Z10–14, `depth-contours` Z12 seulement, `soundings` Z10–16. Courbes, sondes et dangers restent vides sous Z12. Limite par snapshot : 6 000 objets et 4 Mio.

Les XYZ FastAPI vérifient `0 ≤ x,y < 2^z`, sinon 422. Une tuile GEBCO absente ou hors pyramide renvoie 404. La bathymétrie hors couverture renvoie un PNG transparent valide ; une panne réelle renvoie 503, `no-store` et `Retry-After: 15`.

Les MVT des signalements ne contiennent que les observations actives non expirées, regroupées sous Z9 : `report_id`, `category`, `cluster`, `cluster_count`. Le filtre `report_id` désactive ce regroupement. Cache privé 15 s ; les réponses vectorielles marines (GeoJSON/MVT) utilisent un cache public 300 s, 15 s si dégradées, sauf les sondes toujours `no-store`. Raster régional : 24 h, sauf rendu partiel `no-store` ; GEBCO : un an.

Les observations publiques acceptent `category`, `q` ≤ 120 caractères, `limit` de 1 à 500 (200 par défaut) et `cursor`. Donner les quatre bornes `west/south/east/north` ou aucune ; `south < north`, `west != east`, et `west > east` traverse l’antiméridien. Réutiliser les mêmes filtres avec le `next_cursor` reçu.

Leur réponse contient `items`, `has_more` et, si nécessaire, `next_cursor` ; elle ne publie ni e-mail, ni bateau, ni photo et respecte la visibilité du pseudo. Observations et configuration web utilisent `no-store`. `X-NoWave-Marine-Status` indique l’état des données, notamment `ok`, `degraded` ou `unavailable`.

### Administration

Les routes REST suivantes exigent le Bearer d’un admin actif avec e-mail vérifié.

| Méthode et chemin | Entrée et résultat |
| --- | --- |
| `GET /api/v1/admin/reports` | `page`, `limit`, filtre `status: active\|expired\|removed` → 200 liste paginée |
| `GET /api/v1/admin/reports/{report_id}` | 200 détail, y compris retiré ou expiré |
| `GET /api/v1/admin/users` | `page`, `limit`, filtre `status: active\|suspended` → 200 liste paginée |
| `GET /api/v1/admin/moderation-actions` | `page`, `limit` → 200 audit paginé, en lecture seule |
| `DELETE /api/v1/admin/reports/{report_id}` | `{"reason":"Doublon"}` → 204 |
| `PATCH /api/v1/admin/reports/{report_id}` | `{"status":"active","reason":"Retrait corrigé"}` → 200 détail |
| `PATCH /api/v1/admin/reports/{report_id}/photo` | `{"hidden":true,"reason":"Photo inadaptée"}` → 200 métadonnées photo |
| `PATCH /api/v1/admin/users/{user_id}` | `{"status":"suspended","reason":"Abus"}`, ou statut `active` → 200 profil |

Le motif doit être non vide après retrait des espaces. État déjà appliqué, restauration impossible ou auto-suspension : 409 `moderation_conflict`. Restaurer conserve l’expiration initiale et ne crée pas de nouvelle alerte. Les lectures admin ignorent les préférences de visibilité de l’auteur ; une photo masquée reste sans URL.

Les lectures JSON du navigateur utilisent le cookie obtenu via `/admin/login`, sans Bearer, avec `no-store`. Les formulaires POST de l’admin demandent un jeton CSRF. Session absente ou invalide : 303 vers la connexion ; refus : 403 HTML ; dépendance indisponible : 503 HTML.

| Méthode et chemin | Paramètres et résultat |
| --- | --- |
| `GET /admin/data/reports` | Quatre bornes requises, `west < east`, `south < north` → GeoJSON, 1 000 points maximum et booléen `truncated` |
| `GET /admin/data/reports/{target_id}` | Détail admin |
| `GET /admin/data/users` | `page`, `status`, `search` ≤ 80 caractères → `items`, `page`, `pages`, `total`, par 20 |
| `GET /admin/data/users/{user_id}/reports` | `page` → `items`, `page`, `has_more`, par 20 |

### Réponses et erreurs

`page` va de 1 à 1 000 000, `limit` de 1 à 100 (défauts 1 et 20) pour l’historique des alertes et les listes REST admin. Une page hors fin contient une liste vide : `{"items":[],"page":1,"limit":20,"total":0,"pages":0}`.

Les erreurs JSON REST ont la forme `{"error":{"code":"user_not_found","message":"user profile not found","details":null}}`. Les lectures de session web peuvent utiliser `{error: string}` pour leurs erreurs locales.

Codes usuels : 401 token absent/invalide ; 403 e-mail non vérifié, compte suspendu ou rôle insuffisant ; 404 ressource absente ; 409 conflit ; 422 saisie ou mesure invalide ; 503 dépendance indisponible. `request_validation_error` détaille les champs dans `details` ; `gps_precision_insufficient` signale une précision GPS supérieure à 50 m. Le proxy peut répondre 429 sur quota ou 413 sur corps trop gros, sans JSON garanti.

| Méthode et chemin | Résultat |
| --- | --- |
| `GET /health` | Public ; 200 si FastAPI répond |
| `GET /health/ready` | Public ; 200 si PostgreSQL répond, sinon 503 |
| `GET /version` | Public ; 200 avec `service` et révision `version` |

## Cartographie

Mapbox fournit le fond de carte. Les signalements arrivent en tuiles MVT authentifiées ; les ports, marques, courbes, sondes et dangers en GeoJSON public. Les ouvrages portuaires restent en MVT. GEBCO fournit le fond marin mondial ; EMODnet ajoute le détail régional, masqué sur terre.

Le raster apparaît à Z5. Les ports sont préparés à Z6 et affichés à Z8 ; les marques et dangers ponctuels apparaissent progressivement de Z10 à Z12. Les courbes et sondes sont préparées à Z12 et affichées à Z13.

Le mobile charge d’abord le centre visible et garde les anciennes cellules pendant leur remplacement. Une erreur ou un résultat partiel vide conserve les données précédentes ; seul un vide complet confirme leur absence. Les requêtes dépassées sont annulées, les échecs retentés et les sources restaurées après rechargement du style. Un appui long donne accès aux objets ponctuels masqués par collision. Les caches ne garantissent pas un mode hors ligne illimité.

Les profondeurs sont en mètres et gardent leur datum, la référence verticale. Un datum absent reste inconnu. Les sondes NOAA sont des valeurs ponctuelles publiées ; EMODnet fournit des cellules modélisées sous LAT, parfois interpolées, avec des labels arrondis au mètre ou `<1`. Zoomer au-delà de Z16 n’ajoute pas de mesure. Une panne EMODnet ne déclenche pas de bascule vers NOAA. Les courbes EMODnet sont généralisées ; aucune profondeur n’est calculée à partir d’une couleur.

Ces données ne remplacent pas les cartes officielles et ne servent pas au calcul d’une marge sous quille.

### Sources et licences

Le [registre des sources](https://api.no-wave.fr/api/v1/map/marine-sources) rassemble produits,
liens de licence, DOI et limites. Ces crédits couvrent aussi les données de test de `backend/tests/fixtures/marine/` :

- GEBCO Bathymetric Compilation Group 2026, *The GEBCO_2026 Grid* : domaine public, conditions GEBCO ; fond échantillonné et recoloré par NoWave.
- EMODnet Bathymetry Consortium : *EMODnet Digital Bathymetry (DTM 2024)* et contours 2022, produit UE, CC BY 4.0 ; sélection, conversion de signe, arrondi et transformations NoWave.
- Shom, Balisage maritime et levés bathymétriques archivés : Licence Ouverte 2.0. Shom, Épaves et obstructions 2022 : CC BY-SA 4.0.
- © IGN, BD TOPO, édition WFS 2026-06-15 : Licence Ouverte 2.0 ; transformations NoWave.
- NOAA Office of Coast Survey, ENC Direct to GIS : CC0 1.0.
- © Open Waters: Seamap : CC BY 4.0 ; © OpenStreetMap contributors : ODbL 1.0.

Conserver les crédits visibles, les liens de licence et la mention des transformations.

La base dérivée contenant OSM reste sous ODbL ; les dérivés des épaves et obstructions
Shom restent sous CC BY-SA 4.0. OSM demande un cache d'au moins sept jours,
un User-Agent joignable et aucun téléchargement massif ou préchargement hors ligne.

Pour régénérer le fond GEBCO avec l’environnement Python activé :

```sh
python backend/tools/prepare_gebco_background.py \
  /tmp/gebco-source.dods /tmp/gebco-tid.dods deploy/marine/gebco-2026-v2.tar.gz --download
(cd deploy/marine && shasum -a 256 gebco-2026-v2.tar.gz > gebco-2026-v2.tar.gz.sha256)
```

Contrôler le rendu avant de valider l’archive et son checksum. Une nouvelle source ou palette demande
une nouvelle version d'URL ; conserver les anciennes archives et URL pour les clients installés.

Les anciens dessins d’icônes conservent leurs licences : [Temaki CC0](mobile/assets/icons/buoys/LICENSE-Temaki.md) pour le SVG historique des bouées, [CC0](mobile/assets/icons/fixed-aids/LICENSE-CC0.md) pour les aides fixes. Les scripts `mobile/tool/make_buoy_icons.py` et `make_fixed_aid_icons.py` régénèrent ces anciens dessins, pas les PNG NoWave actuels.

## Tester

Avec l’environnement Python activé :

```sh
ruff check backend deploy/hostinger mobile/tool
for script in deploy/hostinger/*.sh; do bash -n "$script"; done
python -m pytest backend/tests/api backend/tests/unit -q
(cd mobile && dart format --output=none --set-exit-if-changed lib test)
(cd mobile && flutter pub get --enforce-lockfile && flutter analyze --no-pub && flutter test --no-pub --coverage)
npm ci --prefix web
npm run format:check --prefix web
npm test --prefix web
npm run build --prefix web
node --test backend/tests/web/*.cjs
```

Après le build web ci-dessus, lancer les tests PostGIS et navigateur avec Docker, OpenSSL et le port 55433 libre. Ce bloc crée une base jetable et la supprime à la fin :

```sh
(
  set -e
  export COMPOSE_FILE=compose.test.yaml COMPOSE_PROJECT_NAME=nowave-tests
  export NOWAVE_TEST_PORT=55433
  export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
  trap 'docker compose down --volumes --remove-orphans' EXIT
  docker compose up -d --build --wait database
  python -m pytest backend/tests/database -q
  npm ci --prefix backend/tests/browser --ignore-scripts
  (cd backend/tests/browser && npx playwright install --with-deps chromium)
  PYTHON=python npm test --prefix backend/tests/browser
)
```

Les parcours navigateur utilisent une base réelle, avec Firebase, stockage et Mapbox simulés. `mapbox.spec.cjs` utilise la vraie carte seulement si `NOWAVE_MAPBOX_CONFIG` fournit un jeton ; sinon il est ignoré. Les résultats sont dans `backend/tests/browser/test-results/`.

Sur téléphone, vérifier la connexion, le GPS, la caméra, la publication avec photo et l’ouverture des alertes au premier plan, en arrière-plan et après arrêt de l’app. Les tests simulés ne valident pas FCM, Scaleway ou la version réellement déployée.

Pour reproduire les audits CI, depuis une copie propre du commit et avec Docker démarré :

```sh
python -m pip install pip-audit==2.10.1
npm audit --prefix web --audit-level=low
pip-audit --require-hashes --disable-pip -r backend/requirements.lock
pip-audit --disable-pip --no-deps -r backend/requirements-test.txt
bash deploy/hostinger/build-and-audit.sh "$(git rev-parse HEAD)"
```

## Déployer

Un push sur `dev` déclenche les tests, les audits et le déploiement du même commit sur le VPS. Les PR et les lancements manuels ne déploient pas. Les releases stables passent de `dev` vers `main` après recette.

L’environnement GitHub `production` attend la variable `NOWAVE_DEPLOY_HOST` et les secrets `NOWAVE_DEPLOY_SSH_KEY`, `NOWAVE_DEPLOY_KNOWN_HOSTS`.

Sur le VPS, les paramètres sont dans `/opt/nowave/config` et les secrets dans `/opt/nowave/secrets` :

- `tunnel_token` pour Cloudflare ; `firebase_service_account.json` du projet `blueway-dev`, autorisé à envoyer les notifications FCM, et `firebase_web_api_key` pour l’admin.
- `photo-storage.env` avec `PHOTO_STORAGE_BUCKET` et `PHOTO_STORAGE_REGION`, puis `scaleway_access_key` et `scaleway_secret_key`. Le bucket reste privé, sans versioning ; la clé doit autoriser lecture, écriture, suppression et listing de `reports/`.
- `MAPBOX_PUBLIC_TOKEN` à injecter dans l’API ; le Compose de production ne le transmet pas par défaut.
- Volume `marine-cache` persistant ; conserver ses fichiers SQLite, WAL et SHM ensemble.

Les fichiers attendus et les limites des services sont dans `deploy/compose.yaml` et `deploy/tunnel.yaml`. Le script `deploy/hostinger/deploy.sh` sauvegarde, migre, démarre les services et contrôle les accès publics avant de promouvoir la version. En cas d’échec, il remet l’application et le tunnel précédents ; il ne restaure pas automatiquement les données SQL. Une sauvegarde tourne aussi chaque jour.

Après livraison, comparer `/version` au commit attendu, vérifier les workers, puis tester une publication avec photo et une alerte sur un second appareil. Nginx répond 429 en cas de limitation ; une dépendance indisponible peut donner 503.

## Contribuer

Créer une branche depuis `dev` à jour, faire des commits ciblés et ouvrir une PR avec les résultats des tests. Un autre membre relit avant la fusion. Pas de développement ni de push direct sur `dev` ou `main`.

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).
