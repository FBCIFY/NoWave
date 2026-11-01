# Tests navigateur de l'administration

## Aperçu sans base de données

Depuis la racine, avec Python 3.12 et les dépendances du backend :

```bash
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

Dans un second terminal :

```bash
npm ci --prefix web
npm run dev --prefix web
```

Ouvrir `http://127.0.0.1:5173/admin/login`, puis utiliser
`admin@nowave.test` / `preview-only`. Les données sont en mémoire, les mutations
sont désactivées et Firebase n'est pas appelé. Le serveur écoute seulement en
local et refuse `NOWAVE_ENV=production`.

Pour afficher Mapbox, définir `MAPBOX_PUBLIC_TOKEN` ou `NOWAVE_MAPBOX_CONFIG`
(chemin d'un JSON contenant `MAPBOX_ACCESS_TOKEN` public). Les tuiles GEBCO sont
extraites temporairement puis supprimées à l'arrêt.

## Tests avec PostGIS

Prérequis : Python 3.12, `backend/requirements-test.txt`, Node.js 24 et Docker.
Depuis la racine :

```bash
COMPOSE_PROJECT_NAME=nowave-admin-test docker compose -f compose.test.yaml up -d --build --wait database
npm ci --prefix web
npm run build --prefix web
npm ci --prefix backend/tests/browser --ignore-scripts
(cd backend/tests/browser && npx playwright install --with-deps chromium)
PYTHON=python3.12 \
NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci \
npm test --prefix backend/tests/browser
COMPOSE_PROJECT_NAME=nowave-admin-test docker compose -f compose.test.yaml down --volumes
```

Le serveur HTTPS écoute sur `127.0.0.1:8765`. Il crée une base aléatoire puis
la supprime ; utiliser uniquement PostgreSQL/PostGIS local. Les mots de passe
sont des fixtures sans compte Firebase réel. `CHROMIUM_EXECUTABLE` permet
d'utiliser un Chromium déjà installé.

| Suite | Périmètre |
| --- | --- |
| `admin.spec.cjs` | FastAPI, Jinja, session HTTPS, CSRF, rôles, lectures et modération PostGIS ; Firebase, stockage et Mapbox simulés |
| `mapbox.spec.cjs` | Mapbox et ses API réels, GEBCO local et API admin sur la base de test ; identité et stockage simulés |

Les tests Mapbox exigent `NOWAVE_MAPBOX_CONFIG`, sinon ils sont ignorés.
Le scénario de catégorie inconnue remplace seulement la réponse cartographique.
Les résolutions sont 1440×1000 et 390×844 tactile. Captures, traces et rapport JSON
sont dans `backend/tests/browser/test-results/`, ignoré par Git. La CI PostGIS
exécute `admin.spec.cjs`.

Ces suites ne valident ni Firebase réel ni le bucket Scaleway. Tester ces accès
avec des comptes et des données de recette dédiés.
