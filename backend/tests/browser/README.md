# Recette navigateur de l'administration

## Aperçu visuel sans base de données

Depuis la racine du dépôt, avec Python 3.12 et les dépendances du backend :

```bash
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

Le serveur n’écoute que sur `127.0.0.1`. Dans un second terminal, lancer
`npm run dev --prefix web`, puis ouvrir `http://127.0.0.1:5173/admin/login`.
La connexion synthétique est `admin@nowave.test` / `preview-only`. Les listes,
fiches, carte et audit utilisent des exemples en mémoire ; les changements métier
sont désactivés. Aucun compte Firebase ni PostgreSQL n’est utilisé.

Les tuiles GEBCO sont extraites temporairement depuis le dépôt puis supprimées à
l’arrêt. Pour la carte Mapbox réelle, définir `MAPBOX_PUBLIC_TOKEN` ou
`NOWAVE_MAPBOX_CONFIG` (JSON local contenant `MAPBOX_ACCESS_TOKEN` public `pk.*`).
Sans jeton, les pages restent consultables et la landing affiche son repli.
Les détails marins utilisent les mêmes routes publiques que l’application.
Le processus refuse `NOWAVE_ENV=production` et n’est jamais importé par le serveur
de production. Cet aperçu ne remplace pas les tests d’intégration ci-dessous.

## Tests d’intégration avec PostgreSQL

Les tests créent une base aléatoire dans PostgreSQL/PostGIS local et la suppriment à l'arrêt. Le serveur HTTPS n'écoute que sur `127.0.0.1:8765`. Ne jamais lui fournir une base distante. Les mots de passe figurant dans les tests sont des fixtures, sans compte Firebase correspondant.

Depuis la racine du dépôt, avec Python 3.12 et les dépendances de `backend/requirements-test.txt` :

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

`CHROMIUM_EXECUTABLE` permet de sélectionner un Chromium déjà installé. Les deux résolutions sont 1440×1000 et 390×844 (tactile).

- `admin.spec.cjs` : navigateur réel, routes FastAPI, Jinja, cookies HTTPS, CSRF, contrôles de rôle, lectures et modération PostgreSQL réels ; fournisseur d'identité Firebase, stockage photo et Mapbox simulés. Cette suite est exécutée par le job CI PostGIS.
- `mapbox.spec.cjs` : Mapbox GL JS réel, API Mapbox réelle, GEBCO du dépôt servi par un alias local, API administrative réelle sur la base synthétique. Le dernier scénario de catégorie inconnue remplace seulement la réponse cartographique. L'identité et le stockage photo restent simulés. Fournir explicitement `NOWAVE_MAPBOX_CONFIG=/chemin/vers/fichier.json`, contenant `MAPBOX_ACCESS_TOKEN` public ; sans ce fichier, ces deux tests sont ignorés. Aucun secret n'est stocké dans le dépôt.

Les captures, traces d'échec et rapports JSON sont dans `test-results/` (ignoré par Git). La CSP provient exactement de la configuration Nginx suivie. Les tuiles terrain vides en plein océan peuvent répondre `404 {"message":"Tile not found"}` ; elles sont recensées séparément, les autres erreurs HTTP et les erreurs Mapbox font échouer le test.

Cette recette ne prouve pas une connexion Firebase réelle ni l'accès au stockage Scaleway réel. Utiliser un compte et des services de test explicitement isolés pour cette validation complémentaire. Ne jamais modérer les données de production.
