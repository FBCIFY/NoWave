# Backend FastAPI

## Installation locale

Depuis la racine du dépôt :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
cp .env.example .env
```

Compléter `.env`, puis démarrer PostgreSQL :

```bash
docker compose up -d database
```

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
cette URL en `postgresql+psycopg://` pour SQLAlchemy. Docker Compose utilisait
déjà le format standard avec le service `database` et son port interne `5432`.

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

### Upload d'une photo de signalement

`POST /api/v1/reports/{report_id}/photo` attend un champ multipart `file` de type
`image/jpeg`. Un propriétaire actif peut envoyer la photo de son signalement.
Le serveur décode réellement le JPEG, refuse les EXIF, les fichiers vides,
corrompus ou supérieurs à 500 000 octets. Flutter doit corriger l'orientation
et supprimer les EXIF avant l'envoi. Les octets acceptés restent inchangés.

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
n'est perdu au redémarrage puisque le bucket est rescanné. Réserver ce préfixe à
NoWave et utiliser un bucket privé sans versioning pour cette politique de purge.
Les anciennes versions d'un bucket versionné exigeraient une politique distincte.

En développement, activer le worker avec `docker compose --profile photos up -d`.
La production le démarre avec l'API. Il s'agit d'entretien du stockage serveur ;
aucune file locale ni reprise mobile après fermeture du parcours n'est ajoutée.

Les requêtes multipart sont limitées à 512 000 octets avant parsing, pour laisser
une marge d'enveloppe au JPEG de 500 000 octets. Nginx conserve sa limite de 32 Ko
sur les autres routes. Le décodage et les appels synchrones SQL/S3 s'exécutent dans
le pool de threads FastAPI. Les doublures des tests ne prouvent pas les droits
Scaleway réels ni la lecture d'une URL expirée : voir la recette du déploiement.

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
