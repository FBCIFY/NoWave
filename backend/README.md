# Backend NoWave

API FastAPI, PostgreSQL/PostGIS, identité Firebase et photos Scaleway.
Les [contrats HTTP](../docs/API.md) regroupent routes, entrées, réponses et erreurs.

## Lancer en local

Prérequis : Python 3.12 et Docker Compose. Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements.txt
cp .env.example .env
```

Compléter `.env`, puis lancer :

```sh
docker compose config --quiet
docker compose up -d --wait database
set -a
. .env
set +a
export GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_FILE"
(cd backend && alembic -c alembic.ini upgrade head)
PYTHONPATH=backend python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

L'API écoute sur `localhost:8000` ; `/docs` expose l'OpenAPI en développement.
Le [README principal](../README.md) donne le démarrage de la pile Docker complète.

## Configuration

| Variable | Usage |
| --- | --- |
| `NOWAVE_DB_PASSWORD`, `NOWAVE_DB_PORT` | PostgreSQL local dans Compose ; défaut du port : 55432 |
| `DATABASE_URL` | URL PostgreSQL du backend Python et des migrations ; même mot de passe que Compose |
| `GOOGLE_CLOUD_PROJECT` | Projet Firebase de l'app, actuellement `blueway-dev` |
| `FIREBASE_SERVICE_ACCOUNT_FILE` | Fichier Firebase local monté par Compose ; le lancement Python ci-dessus l'affecte à `GOOGLE_APPLICATION_CREDENTIALS` |
| `FIREBASE_WEB_API_KEY` | Connexion de l'administration web |
| `MAPBOX_PUBLIC_TOKEN` | Jeton public `pk.*` des cartes web |
| `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION` | Bucket privé Scaleway ; région `fr-par`, `nl-ams` ou `pl-waw` |
| `SCW_ACCESS_KEY`, `SCW_SECRET_KEY` | Clés du stockage photo |

Les clés Scaleway et `FIREBASE_WEB_API_KEY` acceptent aussi `_FILE` ; ne pas
fournir simultanément valeur et fichier. Garder secrets et `.env` hors de Git.
Python joint `localhost:55432`, l'API Docker joint `database:5432`.
Changer `.env` ne renomme pas une base existante : conserver le volume.

[Tests](../docs/TESTING.md) · [Administration web](app/web/README.md) ·
[Déploiement VPS](../deploy/README.md)
