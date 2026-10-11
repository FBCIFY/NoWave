# Backend FastAPI

## Installation locale

Depuis la racine du dépôt :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cp .env.example .env
```

Compléter `.env` avec le même mot de passe local dans `NOWAVE_DB_PASSWORD` et
`DATABASE_URL`. Par exemple (remplacer le mot de passe) :

```dotenv
NOWAVE_DB_PASSWORD=mot-de-passe-local
NOWAVE_DB_PORT=55432
DATABASE_URL=postgresql://nowave:mot-de-passe-local@localhost:55432/nowave
GOOGLE_CLOUD_PROJECT=blueway-dev
FIREBASE_SERVICE_ACCOUNT_FILE=./chemin-vers-le-compte-de-service-firebase.json
```

`NOWAVE_DB_PASSWORD` sert à Docker Compose ; `DATABASE_URL` sert au backend et
aux migrations lancés sur le poste. Les anciens noms `BLUEWAY_DB_PASSWORD` et
`BLUEWAY_DB_PORT` ne sont plus lus par Compose. Le projet Firebase reste
`blueway-dev` : il est indépendant du nom de la base PostgreSQL `nowave`.
Docker Compose monte le fichier `FIREBASE_SERVICE_ACCOUNT_FILE` en lecture seule
pour vérifier les jetons Firebase de l'application mobile.
L'application mobile lit encore une autre configuration, `mobile/.env.json`,
via `--dart-define-from-file`.

Vérifier la configuration et démarrer PostgreSQL :

```bash
docker compose config --quiet
docker compose up -d --wait database
```

Si un volume `nowave-database` existe déjà, vérifier sa base et ses données
avant de modifier son initialisation. Changer `.env` ne renomme pas une base
déjà créée ; ne pas supprimer le volume pour résoudre une erreur de connexion.

Charger les variables et appliquer les migrations :

```bash
set -a
source .env
set +a

cd backend
alembic -c alembic.ini upgrade head
cd ..
```

Lancer FastAPI :

```bash
PYTHONPATH=backend python -m uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8000
```

## Configuration PostgreSQL

Pour un backend lancé directement sur le poste :

```dotenv
DATABASE_URL=postgresql://nowave:mot-de-passe@localhost:55432/nowave
```

Psycopg utilise directement `postgresql://`. Alembic convertit automatiquement
cette URL en `postgresql+psycopg://` pour SQLAlchemy. Dans Docker Compose,
le backend joint le service `database` sur son port interne `5432`.

Le backend réutilise les connexions via un pool par processus, de 1 à 15
connexions. Chaque emprunt vérifie que la connexion fonctionne ; après une
opération, sa transaction est validée ou annulée avant le retour au pool.
L'attente d'une connexion est limitée à 3 secondes. Si la base ne répond pas,
les routes concernées renvoient toujours 503. La production utilise actuellement
un processus Uvicorn ; avec plusieurs processus, chaque processus possède son
propre pool de 15 connexions maximum.

## Authentification Firebase

Les endpoints utilisateur vérifient le token Firebase transmis par
l’application mobile.

En développement local, installer Google Cloud CLI puis exécuter :

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project blueway-dev
```

Les identifiants Google locaux et les clés privées de compte de service ne
doivent jamais être ajoutés à Git.

Le stockage des photos utilise un bucket privé **Scaleway Object Storage**.
Firebase reste utilisé pour l'authentification. Configurer le stockage hors de Git :

```dotenv
PHOTO_STORAGE_BUCKET=nom-du-bucket-prive
PHOTO_STORAGE_REGION=fr-par
SCW_ACCESS_KEY=cle-acces
SCW_SECRET_KEY=cle-secrete
```

Les deux clés acceptent aussi les variantes `SCW_ACCESS_KEY_FILE` et
`SCW_SECRET_KEY_FILE`, utilisées par les secrets Docker de production.

## Endpoints principaux

- `GET /health` vérifie que FastAPI répond.
- `GET /health/ready` vérifie la connexion PostgreSQL.
- `GET /api/v1/users/me` récupère le profil courant sans le créer.
- `POST /api/v1/users/me` crée le profil de l’utilisateur vérifié.
- `PATCH /api/v1/users/me` modifie le profil.
- `DELETE /api/v1/users/me` supprime le profil.

Les conflits de création de profil renvoient `409` avec un code distinct :
`user_already_exists` si l'UID Firebase possède déjà un profil,
`username_already_exists` si le nom est pris, et `email_already_registered`
si l'adresse e-mail appartient à un autre profil. Ce dernier code ne signifie
pas qu'un profil existe pour l'UID Firebase courant.

### Suppression de compte

La suppression conserve l'ordre SQL puis Firebase. Si la suppression SQL a
déjà réussi mais que la suppression Firebase échoue, une nouvelle requête
reprend directement à l'étape Firebase. L'absence de la ligne SQL ne bloque
donc pas la reprise.

Une identité Firebase déjà absente est considérée comme supprimée afin de
rendre l'opération idempotente.

Pour le MVP, la vérification d'authentification conserve le contrôle standard
du jeton Firebase sans contrôle systématique de révocation à chaque requête.
Cette option sera réévaluée si le besoin de révocation immédiate justifie le
coût et la dépendance supplémentaires.

Le profil chargé par le contrôle d'accès est réutilisé par les services pendant
la même requête HTTP. Il n'est jamais mis en cache entre utilisateurs ou entre
requêtes : le statut du compte est relu à chaque appel. Un envoi GPS normal
effectue ainsi cinq instructions SQL métier au lieu de six, hors transactions
et vérification de connexion.

### Upload d'une photo de signalement

`POST /api/v1/reports/{report_id}/photo` attend un champ multipart `file` de type
`image/jpeg`. Un propriétaire actif peut envoyer la photo de son signalement.
Le serveur lit d'abord l'en-tête JPEG sans charger le raster. Il refuse les
EXIF, les fichiers vides, corrompus ou supérieurs à 500 000 octets, ainsi que
les images dépassant 1600 px en largeur ou hauteur ou 2 560 000 pixels.
Ces dimensions correspondent au plafond produit par `prepareReportJpeg` dans
Flutter. Le raster n'est chargé qu'après ces contrôles. Flutter doit corriger
l'orientation et supprimer les EXIF avant l'envoi. Les octets acceptés restent
inchangés.

```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@photo.jpg;type=image/jpeg" \
  https://api.no-wave.fr/api/v1/reports/$REPORT_ID/photo
```

```json
{"report_id":"…","upload_status":"uploaded","size_bytes":421350,"mime_type":"image/jpeg"}
```

Le premier succès renvoie `201`, le même JPEG renvoyé après une réponse perdue
renvoie `200`, un contenu différent après finalisation renvoie `409`. Aucun
nouveau signalement ni seconde ligne photo n'est créé. Le POST ne signe aucune
URL : `GET /api/v1/reports/{id}` fournit une URL de lecture de cinq minutes
uniquement pour une photo uploadée, non masquée, d'un signalement visible.
Une URL déjà émise expire normalement même si la photo est masquée entre-temps.

Chaque tentative non finalisée reçoit une clé d'objet unique contenant l'empreinte
SHA-256 du JPEG. Un retry déjà finalisé compare cette empreinte et réutilise la
photo. Une ancienne suppression retardée ne peut donc pas toucher l'objet d'une
nouvelle tentative, même si la connexion SQL ayant porté le verrou a été perdue.

Les uploads et le nettoyage prennent le même verrou PostgreSQL sur la ligne
photo, jusqu'au commit. Les appels de stockage utilisent des délais de connexion
et de lecture courts, sans retry automatique du SDK. Une panne de stockage
conserve le signalement et passe la photo à `failed`. Une panne SQL ou une réponse
de commit perdue donne `503` : le client peut répéter le même upload, qui relit
l'état réellement commité. Aucune suppression immédiate ne risque de détruire
un objet après un commit dont la réponse a été perdue.

Le worker `python -m app.workers.photo_cleanup` recherche toutes les cinq minutes
les objets `reports/{report_id}/{SHA256}/{tentative_uuid}.jpg` âgés d'au moins une heure. Sous le même
verrou, il supprime uniquement ceux que la ligne photo ne référence plus. Les
photos référencées, même masquées ou expirées, sont conservées. Un échec de
suppression est journalisé et retenté au passage suivant ; aucun état de nettoyage
n'est perdu au redémarrage puisque le bucket est rescanné. Les références SQL
sont lues sans verrou par lots de 250 objets admissibles ; les objets encore
référencés, y compris les photos masquées ou expirées, sont ignorés. Seuls les
candidats à la suppression prennent le verrou d'upload, avec une seconde
vérification de leur référence après acquisition. Le listing paginé du bucket
reste complet pour retrouver aussi les objets orphelins après une panne, sans
charger tout le stock en mémoire. Réserver ce préfixe à
NoWave et utiliser un bucket privé sans versioning pour cette politique de purge.
Les anciennes versions d'un bucket versionné exigeraient une politique distincte.

En développement, activer le worker avec `docker compose --profile photos up -d`.
La production le démarre avec l'API. Il s'agit d'entretien du stockage serveur ;
aucune file locale ni reprise mobile après fermeture du parcours n'est ajoutée.

Les requêtes multipart sont limitées à 512 000 octets avant parsing, pour laisser
une marge d'enveloppe au JPEG de 500 000 octets. Nginx conserve sa limite de 32 Ko
sur les autres routes. Le décodage et les appels synchrones SQL/S3 s'exécutent dans
le pool de threads FastAPI. Le chargement du raster JPEG est limité à quatre
décodages simultanés. À la borne de 1600 x 1600, un raster RGB représente
environ 7,3 Mio d'octets de pixels décodés en mémoire, soit environ 29,3 Mio pour quatre
rasters, hors buffers et mémoire du processus. Le conteneur API reste limité à
384 Mio ; la validation de déploiement doit confirmer la marge par une mesure
RSS sous concurrence. Les doublures des tests ne prouvent pas les droits
Scaleway réels ni la lecture d'une URL expirée : voir la recette du déploiement.

### Modération

Les routes `/api/v1/admin` exigent un profil actif de rôle `admin` : sinon
`403 admin_required` (ou `403 user_inactive` pour un admin suspendu). Chaque
action attend un motif `reason` non vide après suppression des espaces, sinon
`422`.

- `DELETE /api/v1/admin/reports/{id}` avec `{"reason": "…"}` retire le
  signalement et renvoie `204`.
- `PATCH /api/v1/admin/reports/{id}` avec `{"status": "active", "reason": "…"}`
  restaure un signalement retiré et renvoie son détail.
- `PATCH /api/v1/admin/reports/{id}/photo` avec `{"hidden": true, "reason": "…"}`
  masque une photo uploadée et renvoie ses métadonnées.
- `PATCH /api/v1/admin/users/{id}` avec `{"status": "suspended" | "active",
  "reason": "…"}` suspend ou réactive un compte et renvoie son profil public.

Le changement et la ligne `moderation_actions` sont écrits dans la même
transaction, sous verrou de la ligne ciblée. Un état incompatible (rapport déjà
retiré, photo déjà masquée ou non uploadée, compte déjà suspendu, auto-suspension)
renvoie `409 moderation_conflict` sans écrire d'audit. Si l'administrateur est
suspendu pendant la requête, le trigger d'audit refuse l'insertion, tout est
annulé et la route renvoie `403 admin_required`.

La restauration ne prolonge jamais la durée de vie : `expires_at` reste
inchangé, le statut redevient `active` avant expiration, sinon `expired`. La
version du signalement n'est pas incrémentée, aucune nouvelle alerte n'est donc
produite. Une photo masquée conserve son statut d'upload et ne reçoit plus
d'URL de lecture. Un compte suspendu conserve ses signalements, mais
`get_current_identity` lui refuse toute route authentifiée : il ne peut plus
publier ni envoyer de position. Le futur worker d'alertes devra en plus ignorer
les comptes suspendus et les signalements retirés au moment de l'envoi.

#### Lectures administrateur

Ces routes en lecture seule servent de contrat JSON aux pages Jinja
d'administration :

- `GET /api/v1/admin/reports?page=1&limit=20&status=removed` liste tous les
  signalements, du plus récent au plus ancien. `status` (`active`, `expired`,
  `removed`) est optionnel.
- `GET /api/v1/admin/reports/{id}` renvoie le `ReportDetail` complété de
  `removed_at`, de l'auteur (`id`, `username`, `email`, `status`, `deleted`) et
  de `photo.hidden_at`. Il reste lisible pour un signalement retiré ou expiré.
- `GET /api/v1/admin/users?status=suspended` liste les comptes avec leur rôle,
  leur statut, leur e-mail et leur nombre de signalements.
- `GET /api/v1/admin/moderation-actions` liste l'audit, de la plus récente à la
  plus ancienne action. Aucune route ne modifie ni ne supprime une entrée.

Les listes acceptent `page` (défaut `1`) et `limit` (défaut `20`, maximum
`100`) et renvoient `{"items": [...], "page": 1, "limit": 20, "total": 0,
"pages": 0}`. Une page au-delà de la dernière renvoie `items` vide. Le total et
la page sont lus dans le même instantané PostgreSQL.

Aucun job ne réécrit le statut d'un signalement expiré : ces vues affichent
`expired` dès que `expires_at` est passé, même si la ligne vaut encore `active`.
La vue admin ignore les choix de visibilité de l'auteur (nom, bateau). Elle
signe une URL photo de cinq minutes même pour un signalement retiré ou expiré,
mais jamais pour une photo masquée. Une entrée d'audit dont l'administrateur ou
la cible a été supprimé reste listée avec un identifiant `null`.

### Administration web

Les pages d'administration sont rendues par FastAPI avec Jinja, sur le même
domaine que le site : `https://no-wave.fr/admin`. Elles n'utilisent pas de
JavaScript, la CSP du site reste donc inchangée.

| Route | Rôle |
|---|---|
| `GET /admin/login` | Formulaire de connexion |
| `POST /admin/login` | Vérifie le mot de passe puis ouvre la session |
| `GET /admin` | Accueil, réservé à un administrateur actif |
| `POST /admin/logout` | Ferme la session du navigateur |

- **Connexion :** FastAPI envoie l'e-mail et le mot de passe à Firebase
  (`accounts:signInWithPassword`), vérifie le token obtenu, puis applique la
  même règle que `/api/v1/admin` (`resolve_active_admin`) : e-mail vérifié,
  profil actif et rôle `admin`. Ce n'est qu'ensuite qu'il crée un session
  cookie Firebase. Un compte refusé ne reçoit donc jamais de session.
- **Session :** cookie `__Host-nowave_admin_session`, valable 8 h, `HttpOnly`,
  `Secure`, `SameSite=Strict`. À chaque page, le cookie est vérifié auprès de
  Firebase (révocation comprise) et le profil est relu : une suspension
  s'applique dès la requête suivante.
- **CSRF :** chaque formulaire `POST` contient un champ caché `csrf_token`.
  - Formulaire de connexion : pas encore de session, le champ doit être égal
    au cookie `__Host-nowave_admin_csrf` (double submit). Ce cookie est
    supprimé une fois connecté.
  - Pages connectées : le jeton est calculé par le serveur à partir du cookie
    de session (SHA-256). Il change à chaque nouvelle session et ne sert plus
    à rien après la déconnexion.
- **Contrat pour les pages Jinja (`app/web/security.py`) :**
  - `AdminSecurity.require_active_admin(request) -> AdminContext`, où
    `AdminContext` contient `subject` (le `User` admin) et `csrf_token`.
    La dépendance `get_admin_context` l'appelle pour une route.
  - `AdminSecurity.verify_csrf(request, context, token)` sur chaque `POST`.
  - `AdminSecurity.logout(request, context) -> Response`.
  - `render_admin_page` fournit `admin` et `csrf_token` au template.
- **Erreurs :** session absente ou invalide → redirection vers
  `/admin/login` (le cookie n'est effacé que s'il a été envoyé et refusé).
  Compte non admin, suspendu ou sans profil NoWave → page `403`. Firebase ou
  base indisponible → page `503`. Les messages techniques ne sont jamais
  affichés.
- **Déconnexion :** elle revérifie d'abord la session et le jeton CSRF, puis
  efface seulement les cookies du navigateur. Les tokens Firebase restent
  valides, donc l'application mobile de l'admin reste connectée. Si Firebase
  ou la base est indisponible, elle répond `503` et le cookie expire seul.

La connexion exige la clé Web API Firebase du projet (la même que celle de
l'application mobile), à fournir hors de Git :

```dotenv
FIREBASE_WEB_API_KEY=cle-web-api
```

Elle accepte aussi `FIREBASE_WEB_API_KEY_FILE`. Sans cette clé, le formulaire
répond `503` mais le reste de l'API démarre normalement.

nginx route `/admin` vers l'API et limite les envois du formulaire de
connexion à 10 par minute et par visiteur (rafale de 5), en plus de la limite
générale.

## Tests

Depuis la racine, avec l’environnement virtuel activé :

```bash
PYTHONPATH=backend python -m pytest backend/tests/api backend/tests/unit
```

Les tests de base de données nécessitent `NOWAVE_TEST_ADMIN_URL` et le droit de
créer une base temporaire :

```bash
PYTHONPATH=backend python -m pytest backend/tests/database
```

Ils créent leur propre base, appliquent les migrations puis la suppriment. Ils
ne doivent jamais réinitialiser la base partagée.


### Tuiles des signalements

`GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` demande un jeton Firebase et renvoie
une tuile Mapbox Vector Tile (`application/vnd.mapbox-vector-tile`). Les paramètres
optionnels `category` et `report_id` filtrent les résultats. Chaque point porte
`report_id` et `category`. Sous le zoom 9, des points proches sont regroupés ;
un cluster porte `cluster=true` et `cluster_count`. Seuls les signalements de
statut `active` dont `expires_at` est futur sont inclus. La réponse a un cache
privé de 15 secondes. Les retraits et les expirations sont pris en compte à
chaque nouvelle requête de tuile.

Décision T10 : le MVP accepte une latence visuelle maximale de 15 secondes liée
au cache privé des tuiles. À chaque nouvelle requête serveur, un signalement
dont `expires_at <= now()` est exclu immédiatement. Aucun job d'expiration
n'est ajouté.

Le calcul PostGIS des tuiles est partagé entre les utilisateurs d'un même
processus API via un cache mémoire de 15 secondes maximum, borné à 512 entrées
et 16 Mio de contenu. Les requêtes simultanées d'une même tuile ne lancent qu'un
calcul. Les coordonnées, la catégorie, le signalement filtré et la connexion
à la base font partie de la clé ; aucune identité ni URL photo n'est stockée.

Chaque appel conserve l'authentification et une lecture SQL de la révision des
signalements. La migration `20261012_0003` ajoute cette révision, modifiée dans
la même transaction que toute écriture sur `reports`, y compris une écriture SQL
directe. La révision et le calcul utilisent le même snapshot PostgreSQL. Un
retrait, une création ou une restauration invalide donc les anciennes tuiles
dans tous les processus au prochain appel. L'expiration la plus proche dans la
tuile borne aussi sa validité, sans attendre une écriture ou la fin des 15 secondes.
Le cache HTTP privé et les réponses de l'API restent inchangés.

Avant de démarrer cette version, appliquer les migrations et les droits runtime
comme d'habitude (`deploy/hostinger/migrate.py` en production). Le rôle runtime
dispose seulement de SELECT sur `map_cache_revision` ; son invalidation passe
par le trigger, sans droit d'écriture direct pour l'API.
