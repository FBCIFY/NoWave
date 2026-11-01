# Tests navigateur admin

Prérequis : Python 3.12, Node.js 24, Docker Compose, OpenSSL et port 55433 libre. Depuis la racine :

```sh
(
  set -e
  python3.12 -m venv .venv
  . .venv/bin/activate
  python -m pip install -r backend/requirements-test.txt
  export COMPOSE_FILE=compose.test.yaml COMPOSE_PROJECT_NAME=nowave-admin-test
  export NOWAVE_TEST_PORT=55433
  export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
  trap 'docker compose down --volumes --remove-orphans' EXIT
  docker compose up -d --build --wait database
  npm ci --prefix web
  npm run build --prefix web
  npm ci --prefix backend/tests/browser --ignore-scripts
  (cd backend/tests/browser && npx playwright install --with-deps chromium)
  PYTHON=python npm test --prefix backend/tests/browser
)
```

Le serveur HTTPS local écoute sur `127.0.0.1:8765`. Les bases de test et le conteneur sont supprimés à la fin ; ne pas utiliser de base distante.
`admin.spec.cjs` teste les rôles, sessions, CSRF et mutations PostGIS ; Firebase, stockage et Mapbox sont simulés.
`mapbox.spec.cjs` utilise Mapbox réel : définir `NOWAVE_MAPBOX_CONFIG` vers un JSON contenant `MAPBOX_ACCESS_TOKEN` public, sinon cette suite est ignorée.
Les tests couvrent 1440×1000 et 390×844 tactile. `CHROMIUM_EXECUTABLE` permet de choisir un Chromium installé.
Rapports, traces et captures : `backend/tests/browser/test-results/`. Firebase et Scaleway réels restent à tester séparément.
