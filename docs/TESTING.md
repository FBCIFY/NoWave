# Tests et contrôles des PR — BLU-50

Chaque PR vers `dev` ou `main` exécute les contrôles **Python**, **Flutter** et
**PostGIS**. Ils sont rejoués après fusion dans `dev` et peuvent être lancés
manuellement. Aucun filtre de fichiers ne peut laisser un contrôle obligatoire
indéfiniment en attente. Un échec de commande fait échouer le contrôle.

## Reproduire les contrôles

Prérequis : Python 3.12, Flutter 3.47.5 (Dart 3.13.4), Docker avec Compose.
Depuis la racine :

```sh
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements-test.txt
ruff check backend
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
réelle à Railway : ces essais restent documentés dans leurs tâches respectives.

## Base temporaire

Ne jamais utiliser les identifiants Railway ou une base partagée pour cette suite.
Le fichier `compose.test.yaml` utilise un conteneur indépendant, le port local
55433 et un stockage mémoire temporaire. Il ne monte pas le volume de développement.
Depuis la racine, avec l'environnement Python activé :

```sh
export COMPOSE_FILE=compose.test.yaml
export COMPOSE_PROJECT_NAME=nowave-ci-local
export NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55433/nowave_ci
trap 'docker compose down --volumes --remove-orphans' EXIT
docker compose up -d --build --wait database
python -m pytest backend/tests/database -q --junitxml=test-results/database.xml
```

La fixture crée une base `nowave_test_<uuid>`, applique les migrations et la
supprime en fin de suite, y compris en cas d'échec. En CI, le conteneur et son
stockage sont également supprimés par une étape `always()`. Les exécutions GitHub
utilisent des runners indépendants et des noms de projet Compose distincts.
Pour plusieurs exécutions locales simultanées, changer à la fois
`COMPOSE_PROJECT_NAME`, `NOWAVE_TEST_PORT` et le port de `NOWAVE_TEST_ADMIN_URL`.

La suite vérifie schéma, contraintes, migrations, repositories, PostGIS et le
readiness HTTP contre une vraie base migrée. `/health/ready` conserve son contrat :
connexion PostgreSQL, sans garantir à lui seul l'état des migrations ou PostGIS.

## Résultats et revue

La page des contrôles de chaque PR renvoie vers l'exécution GitHub Actions.
Les rapports JUnit Python/PostGIS, le journal PostGIS, le rapport Flutter JSON
et la couverture LCOV sont conservés 14 jours, y compris les rapports disponibles
après un échec. Un résumé est affiché dans chaque job. La couverture est publiée
sans seuil arbitraire bloquant pour ce premier socle.

Joindre dans la PR et Linear : commit testé, lien de l'exécution, commandes,
résultats attendus/observés et limites. Pour prouver la détection d'un échec,
utiliser une PR de vérification temporaire avec une assertion volontairement
fausse, conserver le lien rouge, corriger puis conserver le lien vert. Ne jamais
fusionner l'assertion volontairement fausse.

L'administrateur du dépôt doit rendre obligatoires les contrôles **Python**,
**Flutter** et **PostGIS** dans les règles de branches, en préservant l'approbation
d'un autre membre. Vérifier les noms exacts après la première exécution.
Le compte ayant préparé BLU-50 dispose du droit de pousser, pas d'administrer les
règles. Une CI visible ne prouve donc pas à elle seule le blocage de la fusion.
Après approbation, fusionner dans `dev` et vérifier le nouvel ensemble de contrôles.

Références : BLU-50, Technical Documentation NoWave Stage 3 (QA/SCM), Stage 4.
La base persistante de recette Railway appartient à BLU-57, jamais à cette suite.
