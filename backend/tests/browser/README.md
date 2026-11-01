# Tests navigateur admin

Prérequis : Python 3.12 avec `backend/requirements-test.txt`, Node.js 24 et Docker.
Depuis la racine, dans un shell dédié ; le port 55433 doit être libre :

```sh
export COMPOSE_FILE=compose.test.yaml
export COMPOSE_PROJECT_NAME=nowave-admin-test
export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
trap 'docker compose down --volumes --remove-orphans' EXIT
docker compose up -d --build --wait database
npm ci --prefix web
npm run build --prefix web
npm ci --prefix backend/tests/browser --ignore-scripts
(cd backend/tests/browser && npx playwright install --with-deps chromium)
PYTHON=python3.12 npm test --prefix backend/tests/browser
```

Le serveur de test écoute sur `https://127.0.0.1:8765`. Il crée et supprime sa
base aléatoire dans le PostgreSQL local ; ne pas lui fournir de base distante.
Les tests couvrent 1440×1000 et 390×844 tactile.

- `admin.spec.cjs` : FastAPI, sessions HTTPS, CSRF, rôles et modération PostGIS ;
  Firebase, stockage et Mapbox simulés. Exécuté par la CI PostGIS.
- `mapbox.spec.cjs` : Mapbox réel et GEBCO local ; identité et stockage simulés.
  Définir `NOWAVE_MAPBOX_CONFIG` vers un JSON contenant `MAPBOX_ACCESS_TOKEN`
  public, sinon cette suite est ignorée.

`CHROMIUM_EXECUTABLE` sélectionne un Chromium installé. Les rapports, traces
et captures vont dans `backend/tests/browser/test-results/`, ignoré par Git.
Firebase et Scaleway réels demandent une recette avec des services de test dédiés.


Aperçu en mémoire : [guide web](../../../web/README.md#aperçu-sans-base).
