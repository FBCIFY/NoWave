# Tests

Prérequis : Python 3.12, Flutter 3.47.5, Node.js 24 et Docker Compose. La CI lance Python, Flutter, PostGIS, Web et Admin Web, puis les audits de production.

## Backend

Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
ruff check backend deploy/hostinger mobile/tool
for script in deploy/hostinger/*.sh; do bash -n "$script"; done
python -m pytest backend/tests/api backend/tests/unit -q
```

## Mobile

Depuis `mobile/` :

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --coverage
```

## Web et JavaScript admin

Depuis la racine :

```sh
npm ci --prefix web
npm run format:check --prefix web
npm test --prefix web
npm run build --prefix web
node --test backend/tests/web/*.cjs
```

La CI vérifie aussi la syntaxe JavaScript admin, la configuration Nginx et le démarrage du service web ; les commandes exactes sont dans `.github/workflows/checks.yml`.

## PostGIS

Depuis la racine, avec l’environnement Python activé. Ce bloc utilise une base jetable sur le port 55433 et la supprime à la sortie :

```sh
(
  set -e
  export COMPOSE_FILE=compose.test.yaml
  export COMPOSE_PROJECT_NAME=nowave-tests
  export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
  trap 'docker compose down --volumes --remove-orphans' EXIT
  docker compose up -d --build --wait --wait-timeout 120 database
  python -m pytest backend/tests/database -q
)
```

Pour les parcours admin avec navigateur : [tests Playwright](../backend/tests/browser/README.md). Ils utilisent le même port ; les lancer après l’arrêt de la base ci-dessus. La suite Mapbox réelle demande une configuration distincte et ne tourne pas en CI standard.

## Audits de production

Depuis une copie propre du commit, avec l’environnement Python activé et Docker démarré :

```sh
python -m pip install pip-audit==2.10.1
npm ci --prefix web --ignore-scripts
npm audit --prefix web --audit-level=low
pip-audit --require-hashes --disable-pip -r backend/requirements.lock
pip-audit --disable-pip --no-deps -r backend/requirements-test.txt
bash deploy/hostinger/build-and-audit.sh "$(git rev-parse HEAD)"
```

## Recette sur appareil

Vérifier la connexion, le GPS, la caméra, la publication avec photo et l’ouverture des alertes au premier plan, en arrière-plan et après arrêt de l’app. Tester FCM, Scaleway et la version VPS avec les services réels : les doubles de test ne les valident pas.

Dans la PR, noter le commit, l’environnement, les commandes et le résultat ; pour un téléphone, ajouter le modèle et l’OS. Les rapports CI sont conservés 14 jours.
