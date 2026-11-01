# Backend

API FastAPI pour les profils, signalements, photos et alertes, avec PostgreSQL/PostGIS et Firebase.

## Prérequis

- Docker avec Compose et le `.env` de la racine complété.
- Python 3.12 pour lancer les tests sur le poste.

## Lancer

Depuis la racine du dépôt :

```sh
docker compose up --build -d --wait database backend
```

L’API est sur `http://127.0.0.1:8000`, avec l’OpenAPI sous `/docs`. Le port se règle dans `.env` ; les migrations sont automatiques.

## Tests

Depuis la racine, préparer l’environnement puis lancer les tests API et unitaires :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
python -m pytest backend/tests/api backend/tests/unit -q
```

Firebase, le stockage photo et les fournisseurs sont simulés. Pour vérifier la base réelle : [tests PostGIS](tests/README.md).
