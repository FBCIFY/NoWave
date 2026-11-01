# Backend

FastAPI expose les profils, les signalements, les photos et les alertes. Les règles métier sont dans `app/application`, les accès SQL et fournisseurs dans `app/infrastructure`.

Avec Docker Compose et le `.env` de la racine renseigné, lancer depuis la racine du dépôt :

```sh
docker compose up --build -d --wait database backend
curl --fail http://127.0.0.1:8000/health
```

La commande applique les migrations avant de lancer l’API. L’adresse utilise le port par défaut 8000 ; `NOWAVE_API_PORT` permet de le changer. L’OpenAPI est sous `/docs` en développement.

Pour suivre les erreurs pendant une requête :

```sh
docker compose logs -f backend
```

Les photos utilisent un bucket Scaleway privé. Firebase vérifie l’identité ; le profil NoWave porte le rôle, le statut et les préférences. Ces accès se règlent dans `.env`, qui reste hors Git.

## Tests

Les tests API et unitaires tournent sur le poste avec Python 3.12. Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
python -m pytest backend/tests/api backend/tests/unit -q
```

Firebase, le stockage photo et les appels fournisseurs sont simulés dans cette suite. Pour travailler sur une migration ou un repository, lancer aussi les [tests sur PostGIS](tests/README.md).
