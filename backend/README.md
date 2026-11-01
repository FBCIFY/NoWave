# API NoWave

FastAPI gère les profils, les signalements, les photos, les alertes et
l'administration. PostgreSQL/PostGIS stocke les données ; Firebase gère
l'identité et les notifications ; Scaleway stocke les photos dans un bucket privé.

## Lancer l'API en local

Prérequis : Python 3.12 et Docker Compose. Depuis la racine :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cp .env.example .env
```

Compléter `.env` : même mot de passe dans `NOWAVE_DB_PASSWORD` et `DATABASE_URL`,
projet Firebase et chemin du compte de service. Compose utilise
`FIREBASE_SERVICE_ACCOUNT_FILE` ; un lancement Python utilise les identifiants
Google par défaut, ou `GOOGLE_APPLICATION_CREDENTIALS` pointant vers ce fichier.
Garder les clés privées et les fichiers d'environnement hors de Git.

```bash
docker compose config --quiet
docker compose up -d --wait database
set -a
source .env
set +a
export GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_FILE"
(cd backend && alembic -c alembic.ini upgrade head)
PYTHONPATH=backend python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

En local, `DATABASE_URL` joint `localhost:55432`. Dans Compose, l'API joint
`database:5432`. Un changement de `.env` ne renomme pas une base existante :
conserver le volume et vérifier sa configuration avant toute intervention.

Le pool PostgreSQL contient 1 à 15 connexions par processus, avec 3 secondes
d'attente maximum. Une base indisponible donne une réponse `503`.

## Contrats HTTP

Les routes métier sont sous `/api/v1`. En développement, `/docs` présente
l'OpenAPI ; cette interface est désactivée en production.

| Route | Usage |
| --- | --- |
| `GET /health`, `GET /health/ready`, `GET /version` | Processus, connexion SQL, révision |
| `GET/POST/PATCH/DELETE /api/v1/users/me` | Lire, créer, modifier ou supprimer son profil |
| `GET/POST/PATCH/DELETE /api/v1/users/me/boat` | Gérer son bateau |
| `PUT/DELETE /api/v1/devices/current` | Enregistrer ou désactiver son appareil |
| `POST /api/v1/reports`, `GET /api/v1/reports/{id}` | Publier et consulter un signalement |
| `POST /api/v1/reports/{id}/photo` | Envoyer sa photo JPEG |
| `GET /api/v1/users/me/alerts` | Consulter ses alertes reçues |
| `GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` | Charger les signalements sur la carte mobile |
| `GET /api/v1/map/observations` | Charger les observations publiques |
| `GET /api/v1/map/web-config` | Lire le jeton Mapbox public du site |

Les routes utilisateur exigent un token Firebase. La création du profil exige
un e-mail vérifié. `GET /users/me` ne crée aucun profil. Le rôle à l'inscription
est `user` ; l'accès admin exige un profil actif de rôle `admin`.

Les conflits de création donnent `409` avec `user_already_exists`,
`username_already_exists` ou `email_already_registered`. La suppression du compte
efface d'abord les données SQL, puis Firebase ; un nouvel appel reprend l'étape
Firebase si la première suppression a déjà réussi.

## Photos

Configurer `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION`, `SCW_ACCESS_KEY` et
`SCW_SECRET_KEY`. Les clés acceptent aussi un suffixe `_FILE` pour les secrets Docker.

L'upload attend un champ multipart `file`, de type `image/jpeg` :
500 000 octets maximum, 1600 px par côté et 2 560 000 pixels maximum, sans EXIF.
Le mobile prépare l'orientation et retire les métadonnées avant l'envoi.

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -F "file=@photo.jpg;type=image/jpeg" \
  "https://api.no-wave.fr/api/v1/reports/$REPORT_ID/photo"
```

Le premier upload donne `201`, le même JPEG répété donne `200`, un contenu
différent après finalisation donne `409`. Après un `503`, renvoyer le même JPEG.
Une panne du stockage conserve le signalement et marque la photo `failed`.

Le détail du signalement fournit une URL signée valable cinq minutes pour une
photo visible. Masquer la photo bloque les nouvelles URL ; les URL déjà émises
restent valables jusqu'à leur expiration.

Le worker `python -m app.workers.photo_cleanup` passe toutes les cinq minutes.
Il supprime les objets du préfixe `reports/` non référencés depuis au moins une
heure, sous le même verrou que l'upload. Les photos encore référencées sont
conservées, même masquées ou expirées. Utiliser un bucket privé sans versioning.

```bash
docker compose --profile photos up -d photo-cleanup
```

## Alertes de proximité

La publication écrit le signalement, l'historique utilisateur et les tâches FCM
dans la même transaction. Un rejeu de `client_report_id` ne crée pas de doublon.
`select_alert_recipients(cursor, report_id)` utilise le curseur de publication.

PostGIS retient les appareils à 18 520 m au plus, avec une précision GPS de
0 à 50 m. L'auteur, les comptes inactifs, les appareils inactifs ou sans token
et les utilisateurs sans consentement sont exclus. Aucun filtre d'âge de la
position ou de cap n'est appliqué. La distance utilisateur est la plus courte
parmi ses appareils éligibles.

```bash
docker compose --profile alerts up -d notifications
```

Le worker relit l'éligibilité avant l'envoi et garde ses verrous SQL pendant
l'appel FCM. Les échecs temporaires sont repris après 1, 5, 15, 30 puis
60 minutes ; `Retry-After` peut allonger l'attente. Aucun envoi n'est tenté après
expiration. Seule l'erreur `UNREGISTERED` efface le token de l'appareil.

Le payload partage le même `alert_id` entre les appareils et contient
`report_id`, `report_version`, `category`, `distance_m`, `position_dms`,
`position`, `alerted_at` et `expires_at`. Les valeurs `data` sont des chaînes.
Le titre affiche la catégorie et la distance ; le texte reprend le commentaire
sur une ligne, limité à 100 caractères.

`sent` signifie que FCM a accepté le message. Un crash avant le commit peut
entraîner un nouvel envoi avec les mêmes identifiants. Les tâches terminées
sont purgées après sept jours ; l'historique des alertes est conservé jusqu'à
la suppression du compte. `GET /users/me/alerts?page=1&limit=20` renvoie cet
historique du plus récent au plus ancien, sans état lu/non lu.

## Carte

Les tuiles MVT exigent un token Firebase. Elles contiennent les signalements
actifs non expirés et acceptent les filtres `category` et `report_id`.
Sous Z9, les points proches sont regroupés. Le cache HTTP privé dure 15 secondes.
Le cache SQL en mémoire est borné à 512 entrées et 16 Mio ; une révision partagée
invalide les tuiles après écriture, et l'expiration limite leur durée de validité.

`GET /map/observations` est public, en lecture seule, avec `Cache-Control: no-store`.
Filtres : emprise `west/south/east/north`, `category`, `q` (120 caractères),
`limit` (1–500, défaut 200) et `cursor`. Une emprise `west > east` traverse
l'antiméridien. La réponse contient `items`, `has_more` et `next_cursor` ; garder
les mêmes filtres pour la suite. Le tri est `observed_at DESC, id DESC`.
Les pseudonymes respectent le choix de visibilité ; e-mails, photos et données
de bateau restent privés.

`GET /map/web-config` expose uniquement `MAPBOX_PUBLIC_TOKEN` au format `pk.*`,
sans cookie ni accès SQL. Un jeton absent, secret ou malformé donne une chaîne vide.

Les sources et caches marins sont décrits dans les [guides cartographiques](../docs/README.md).

## Administration

L'interface est servie sur `/admin`. Elle exige un e-mail vérifié, un profil
actif de rôle `admin` et `FIREBASE_WEB_API_KEY` (ou sa variante `_FILE`).
La session Firebase dure huit heures ; son cookie est `Secure`, `HttpOnly`
et `SameSite=Strict`. Le rôle et la révocation sont revérifiés à chaque page.
Les formulaires POST vérifient un token CSRF. La déconnexion efface la session
du navigateur et laisse la session mobile ouverte.

| Route admin | Action |
| --- | --- |
| `DELETE /api/v1/admin/reports/{id}` | Retirer un signalement |
| `PATCH /api/v1/admin/reports/{id}` | Restaurer un signalement |
| `PATCH /api/v1/admin/reports/{id}/photo` | Masquer une photo |
| `PATCH /api/v1/admin/users/{id}` | Suspendre ou réactiver un compte |
| `GET /api/v1/admin/reports`, `/users`, `/moderation-actions` | Consulter les listes et l'audit |

Chaque modification exige un motif non vide et écrit l'audit dans la même
transaction. Un conflit d'état donne `409 moderation_conflict`. Une restauration
ne prolonge pas le signalement et ne déclenche pas d'alerte. Les listes utilisent
`page` (défaut 1) et `limit` (défaut 20, maximum 100).

Pour le rendu web partagé et HTTPS local, suivre le [guide admin web](app/web/README.md).
Pour les commandes et les services à valider sur appareil, suivre le
[guide de tests](../docs/TESTING.md).
