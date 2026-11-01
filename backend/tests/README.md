# Tests PostGIS

La suite vérifie les migrations et les repositories sur une base temporaire.

## Prérequis

- Environnement Python des [tests backend](../README.md#tests) activé.
- Docker Compose démarré et port 55433 libre.

## Lancer

Depuis la racine du dépôt :

```sh
(
  set -e
  export COMPOSE_FILE=compose.test.yaml COMPOSE_PROJECT_NAME=nowave-backend-tests
  export NOWAVE_TEST_PORT=55433
  export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
  trap 'docker compose down --volumes --remove-orphans' EXIT
  docker compose up -d --build --wait database
  python -m pytest backend/tests/database -q
)
```

Le conteneur est supprimé à la fin, même si un test échoue. La base de développement n’est pas utilisée.
