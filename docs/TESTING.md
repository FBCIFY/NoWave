# Tests et contrôles NoWave

Le workflow **NoWave CI** (`.github/workflows/checks.yml`) est le point d'entrée
unique. Chaque PR vers `dev` ou `main` exécute en parallèle les contrôles
**Python**, **Flutter**, **PostGIS** et **Web**. Ils sont rejoués après fusion
dans `dev` et peuvent être lancés manuellement depuis ce workflow. Aucun filtre
de fichiers ne peut laisser un contrôle obligatoire indéfiniment en attente.
Un échec de commande fait échouer le contrôle.

Après la réussite des quatre contrôles, `production.yml` est appelé pour auditer
les dépendances et construire/auditer les quatre images de production, sans
rejouer les tests. Il valide aussi les PR vers `main`. Seul un push sur `dev`
peut ensuite déployer la révision testée sur le VPS ; les PR et les lancements
manuels ne déploient jamais. Les anciennes révisions d'une PR sont annulées,
mais un nouveau push sur `dev` n'interrompt pas une livraison en cours.

## Reproduire les contrôles

Prérequis : Python 3.12, Flutter 3.47.5 (Dart 3.13.4), Node.js 24 et Docker
avec Compose.
Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
ruff check backend deploy/hostinger mobile/tool
for script in deploy/hostinger/*.sh; do bash -n "$script"; done
python -m pytest backend/tests/api backend/tests/unit -q --junitxml=test-results/python.xml
```

Le contrôle Ruff vise les erreurs de correction (`E9`, `F63`, `F7`, `F82`).
Il n'impose pas de reformater tout le code Python historique.
Les dépendances de test transitives sont verrouillées dans
`backend/requirements-test.txt`. Pour les renouveler, utiliser Python 3.12 et
`pip-tools==7.6.1`, puis exécuter :

```sh
pip-compile --output-file backend/requirements-test.txt backend/requirements-test.in
```

Depuis `mobile/` :

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --coverage
```

Les tests Flutter utilisent des doubles pour les services externes. Ils ne
valident pas les capteurs, les notifications sur téléphone ni une connexion
réelle à l'API, à Firebase ou au stockage photo. Ils ne compilent pas non plus
les projets natifs Android/iOS : ces essais restent à réaliser sur appareil.

## Site web

Depuis `web/` :

```sh
npm ci
npm run format:check
npm test
npm run build
docker compose config --quiet
docker compose up --build -d --wait --wait-timeout 90
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/health
curl --fail --silent --show-error --max-time 15 http://127.0.0.1:8080/ > /dev/null
docker compose down --volumes --remove-orphans
```

Le build vérifie également les assets utilisés par le site. Le contrôle Docker
teste le service Nginx autonome de `web/` ; les images du VPS sont construites
et auditées séparément avec les Dockerfiles de `deploy/`.

## Base temporaire

Ne jamais utiliser les identifiants de production ou une base partagée pour cette suite.
Le fichier `compose.test.yaml` utilise un conteneur indépendant, le port local
55433 et un stockage mémoire temporaire. Il ne monte pas le volume de développement.
Depuis la racine, avec l'environnement Python activé :

```sh
export COMPOSE_FILE=compose.test.yaml
export COMPOSE_PROJECT_NAME=nowave-ci-local
export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
trap 'docker compose down --volumes --remove-orphans' EXIT
docker compose up -d --build --wait --wait-timeout 120 database
python -m pytest backend/tests/database -q --junitxml=test-results/database.xml
```

La fixture crée une base `nowave_test_<uuid>`, applique les migrations et la
supprime en fin de suite, y compris en cas d'échec. En CI, le conteneur et son
stockage sont également supprimés par une étape `always()`. Les exécutions GitHub
utilisent des runners indépendants et des noms de projet Compose distincts.
Pour plusieurs exécutions locales simultanées, changer à la fois
`COMPOSE_PROJECT_NAME`, `NOWAVE_TEST_PORT` et le port de `NOWAVE_TEST_ADMIN_URL`.

La suite vérifie schéma, contraintes, migrations, repositories, PostGIS, pool
de connexions, cache des tuiles, concurrence des écritures et readiness HTTP
contre une vraie base migrée. `/health/ready` conserve son contrat :
connexion PostgreSQL, sans garantir à lui seul l'état des migrations ou PostGIS.

## Audits de production

Depuis la racine, avec l'environnement Python activé et Docker démarré :

```sh
python -m pip install pip-audit==2.10.1
npm audit --prefix web --audit-level=low
pip-audit --require-hashes --disable-pip -r backend/requirements.lock
pip-audit --disable-pip --no-deps -r backend/requirements-test.txt
bash deploy/hostinger/build-and-audit.sh "$(git rev-parse HEAD)"
```

Le script construit les images API, web, PostgreSQL/PostGIS et tunnel, puis
vérifie leurs vulnérabilités et la configuration de `deploy/`. Lancer cette
commande depuis une copie propre du commit à vérifier : elle utilise les
fichiers présents sur disque. Le marqueur `test-results/production-audit-ok`
n'est écrit qu'après réussite de tous les audits. Le déploiement reconstruit
et réaudite ensuite la même révision sur le VPS ; voir
[la documentation de livraison](../deploy/README.md).

## Résultats et revue

La page des contrôles de chaque PR renvoie vers l'exécution GitHub Actions.
Les rapports JUnit Python/PostGIS, le journal PostGIS, le rapport Flutter JSON,
la couverture LCOV, les sorties des tests web et les logs Nginx sont conservés
14 jours, y compris les rapports disponibles après un échec. Les audits des
images publient leurs rapports JSON et le marqueur de réussite dans un artefact
séparé. Un résumé est affiché dans chaque job de test. La couverture est publiée
sans seuil arbitraire bloquant.

Joindre dans la PR et Linear : commit testé, lien de l'exécution, commandes,
résultats attendus/observés et limites. Pour prouver la détection d'un échec,
utiliser une PR de vérification temporaire avec une assertion volontairement
fausse, conserver le lien rouge, corriger puis conserver le lien vert. Ne jamais
fusionner l'assertion volontairement fausse.

L'administrateur du dépôt doit rendre obligatoires les contrôles **Python**,
**Flutter**, **PostGIS**, **Web** et l'audit **Production / Dependency and image
audits** dans les règles de branches, en préservant l'approbation d'un autre
membre. Vérifier les noms exacts affichés par GitHub après la première exécution.
Les noms des quatre jobs de test sont conservés ; les workflows séparés
`database.yml` et `web.yml` ont été regroupés dans `checks.yml`.
Une CI visible ne prouve pas à elle seule le blocage de la fusion : les règles
GitHub ne sont pas modifiées par ces fichiers. Après approbation, fusionner dans
`dev` et vérifier les contrôles et la livraison.
