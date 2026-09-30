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

## Endpoints principaux

- `GET /health` vérifie que FastAPI répond.
- `GET /health/ready` vérifie la connexion PostgreSQL.
- `GET /api/v1/users/me` récupère le profil courant sans le créer.
- `POST /api/v1/users/me` crée le profil de l’utilisateur vérifié.
- `PATCH /api/v1/users/me` modifie le profil.
- `DELETE /api/v1/users/me` supprime le profil.

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
