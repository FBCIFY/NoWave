# Tester NoWave

La CI est définie dans `.github/workflows/checks.yml`. Les PR vers `dev` ou `main` lancent les contrôles Python, Flutter, PostGIS, Web et Admin Web. Après leur réussite, `production.yml` audite les dépendances et les images Docker. Seul un push validé sur `dev` peut déployer sur le VPS.

Prérequis : Python 3.12, Flutter 3.47.5, Node.js 24 et Docker avec Compose.

## Backend

Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
ruff check backend deploy/hostinger mobile/tool
for script in deploy/hostinger/*.sh; do bash -n "$script"; done
python -m pytest backend/tests/api backend/tests/unit -q --junitxml=test-results/python.xml
```

Ruff vérifie les erreurs de correction. Pour renouveler les dépendances de test, utiliser Python 3.12 et `pip-tools==7.6.1`, puis :

```sh
pip-compile --output-file backend/requirements-test.txt backend/requirements-test.in
```

## Mobile

Depuis `mobile/` :

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --coverage
```

Ces tests simulent les services externes. Vérifier séparément sur téléphone le GPS, la caméra, les capteurs et les notifications réelles.

## Site web

Depuis `web/` :

```sh
npm ci
npm run format:check
npm test
npm run build
docker compose config --quiet
docker compose up --build -d --wait --wait-timeout 90
curl --fail http://127.0.0.1:8080/health
curl --fail http://127.0.0.1:8080/ > /dev/null
docker compose down --volumes --remove-orphans
```

Ce Compose teste le site autonome. Le Compose à la racine lance l’ensemble du projet.

## PostGIS et parcours navigateur

Utiliser uniquement la base jetable de `compose.test.yaml`. Elle écoute sur le port 55433 et ne monte pas le volume de développement. Depuis la racine, avec l’environnement Python activé, dans un shell dédié :

```sh
export COMPOSE_FILE=compose.test.yaml
export COMPOSE_PROJECT_NAME=nowave-ci-local
export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
trap 'docker compose down --volumes --remove-orphans' EXIT
docker compose up -d --build --wait --wait-timeout 120 database
python -m pytest backend/tests/database -q --junitxml=test-results/database.xml
```

La fixture crée une base par suite, applique les migrations, puis la supprime. Pour des exécutions simultanées, changer le nom de projet, `NOWAVE_TEST_PORT` et le port de l’URL.

Pour les parcours admin, garder cette base démarrée et suivre uniquement les étapes npm et Playwright du [guide des tests navigateur](../backend/tests/browser/README.md), sans relancer son démarrage Compose. Les deux projets utilisent le même port. La CI lance `admin.spec.cjs`. Les scénarios avec la vraie carte Mapbox demandent une configuration distincte et ne tournent pas dans la CI standard.

## JavaScript admin

Depuis la racine :

```sh
for file in backend/app/web/static/{login,surveillance,maritime-style,marker-icons,cluster-interaction}.js; do
  node --check "$file"
done
node --test backend/tests/web/*.cjs
```

Le job Admin Web vérifie aussi la configuration Nginx avec l’image épinglée dans le workflow.

## Audits de production

Depuis la racine, avec l’environnement Python activé et Docker démarré :

```sh
python -m pip install pip-audit==2.10.1
npm audit --prefix web --audit-level=low
pip-audit --require-hashes --disable-pip -r backend/requirements.lock
pip-audit --disable-pip --no-deps -r backend/requirements-test.txt
bash deploy/hostinger/build-and-audit.sh "$(git rev-parse HEAD)"
```

Lancer le script depuis une copie propre du commit à vérifier. Il construit et audite les images API, web, PostgreSQL/PostGIS et tunnel. Le marqueur `test-results/production-audit-ok` est créé après réussite. Voir le [guide de déploiement](../deploy/README.md).

## Recette fonctionnelle

| Parcours | Points à vérifier | Tests |
| --- | --- | --- |
| Compte et profil | E-mail vérifié, création explicite du profil, réponse perdue, pseudo déjà pris, préférences et bateau | `backend/tests/api/test_users.py`, `test_boats.py`, `test_devices.py` ; `mobile/test/features/auth/`, `mobile/test/features/profile/` |
| Carte | MVT authentifiées, détail relu à l’ouverture, expiration serveur, couches marines, réponses partielles et rechargement du style | `backend/tests/api/test_map_tiles.py`, `backend/tests/database/test_map_tile_cache.py`, `mobile/test/features/map/` |
| Signalement et photo | Point final confirmé, idempotence de `client_report_id`, JPEG envoyé séparément, nouvel essai sur le même signalement | `backend/tests/api/test_reports.py`, `test_photo_uploads.py`, `test_position_estimates.py` ; `mobile/test/features/reports/` |
| Alertes | Préférence et permission OS, appareil actif, dernière position connue, précision ≤ 50 m, distance de 10 NM, déduplication et ouverture de la carte | `backend/tests/database/test_notification_worker.py`, `backend/tests/api/test_my_alerts.py`, `mobile/test/features/alerts/` |
| Admin | Refus aux comptes non admin ou suspendus, session et CSRF, motif de modération, audit, photo masquée | `backend/tests/api/test_admin_moderation.py`, `test_admin_reads.py`, `test_admin_web.py`, `test_admin_web_pages.py` |
| Livraison | Contrôles verts, SHA de `/version`, workers, sauvegarde et retour arrière | `backend/tests/unit/`, scripts de `deploy/hostinger/` |

Un statut FCM `sent` signifie que FCM a accepté l’envoi. La réception doit être vérifiée sur téléphone. Tester l’ouverture d’une alerte au premier plan, en arrière-plan et après arrêt de l’app, avec et sans GPS.

Les routes de modification et suppression d’un signalement par son auteur, ainsi que `GET /api/v1/users/me/reports`, sont absentes. L’historique `/users/me/alerts` liste les alertes reçues. Le regroupement visuel de points ne prouve pas un regroupement métier à 200 m.

## Conserver les résultats

Dans la PR, indiquer le commit, l’environnement, les commandes, le résultat attendu et observé, puis les limites. Pour un essai sur appareil, ajouter le modèle, l’OS et la date avec le fuseau.

La CI conserve les rapports et logs disponibles pendant 14 jours. Les [résultats du 29 octobre](NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf) et le [suivi des anomalies](NoWave_Rapport_Bug_Tracking.pdf) sont des bilans historiques.

Les protections de branche doivent rendre obligatoires les cinq contrôles et l’audit de production, avec revue d’un autre membre. Une CI verte valide son périmètre ; les essais Android/iOS, FCM, Scaleway et VPS ont leurs propres résultats.
