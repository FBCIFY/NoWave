# Tester sur PostGIS

Ces tests appliquent les migrations et exercent les repositories sur PostgreSQL/PostGIS. La base de développement reste à part.

Activer l’environnement Python préparé dans les [tests backend](../README.md#tests), démarrer Docker et libérer le port 55433. Lancer ce bloc depuis la racine du dépôt :

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

Les fixtures créent leur base temporaire et la suppriment après les tests. Le bloc arrête et nettoie le conteneur, même si un test échoue.

La CI lance cette suite en plus des tests API et unitaires.
