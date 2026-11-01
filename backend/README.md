# Backend NoWave

Lancer FastAPI sur le poste avec PostgreSQL dans Docker. Prérequis : Python 3.12 et Docker Compose. Commandes depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements.txt
test -f .env || cp .env.example .env
```

Compléter `.env` avant la suite : `NOWAVE_DB_PASSWORD`, `DATABASE_URL`, `GOOGLE_CLOUD_PROJECT` et `FIREBASE_SERVICE_ACCOUNT_FILE`.
`DATABASE_URL` doit utiliser le même mot de passe et le port `NOWAVE_DB_PORT` de Compose : `localhost:55432` par défaut.

```sh
set -a
. .env
set +a
docker compose config --quiet
docker compose up -d --wait database
export GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_SERVICE_ACCOUNT_FILE"
(cd backend && alembic -c alembic.ini upgrade head)
PYTHONPATH=backend python -m uvicorn app.main:app --host 127.0.0.1 --port "${NOWAVE_API_PORT:-8000}"
```

L'API écoute sur le port `NOWAVE_API_PORT`, 8000 par défaut. `/docs` expose l'OpenAPI en développement.
Pour les photos : `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION` (`fr-par`, `nl-ams` ou `pl-waw`), `SCW_ACCESS_KEY` et `SCW_SECRET_KEY`.
Pour l'admin web : `FIREBASE_WEB_API_KEY` ; pour sa carte : `MAPBOX_PUBLIC_TOKEN`, jeton public `pk.*`.
Les clés Scaleway et la clé web Firebase acceptent `_FILE` à la place de la valeur directe. Garder secrets et `.env` hors de Git.
Changer `.env` ne renomme pas une base existante : conserver le volume.
