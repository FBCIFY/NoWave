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

## Recette fonctionnelle par parcours (consolidation documentaire du 30/10/2026)

Cette section conserve les scénarios pratiques et les chemins de vérification des
anciens guides `docs/parcours/`. Le contrat métier et les exemples de requêtes
sont définis par la [documentation technique Stage 4](https://docs.google.com/document/d/1Gez2BmfkdjTLyE9jkyf-U_QzJkUWQ9mu/edit).
Les chemins ci-dessous servent à retrouver le code et les tests ; **leur existence
ne démontre pas que les scénarios ont été exécutés avec succès**.

| Parcours | Scénario de recette complémentaire | Code / tests à consulter |
| --- | --- | --- |
| Authentification, profil, bateau | Vérifier séparément identité Firebase, e-mail validé et création explicite du profil par POST ; après une réponse perdue, relire GET sans recréer. Distinguer les erreurs de pseudo déjà pris, profil existant et e-mail lié à un autre compte. Vérifier permissions OS versus consentement NoWave, activation et désactivation de l'installation. | `backend/app/api/routes/users.py`, `boats.py`, `devices.py`, `backend/app/api/dependencies/auth.py` ; `backend/tests/api/test_users.py`, `test_boats.py`, `test_devices.py` ; `mobile/test/features/auth/` et `profile/` |
| Carte et sélection | Vérifier les tuiles de signalements MVT authentifiées et la relecture du détail courant par GET /reports/{id}. Mesurer séparément expiration à l'heure serveur et disparition visuelle (un cache HTTP de 15 s ne garantit pas le délai de retrait dans le SDK). Contrôler également chargement des snapshots GeoJSON marins, maintien d'une ancienne cellule face à une réponse partielle, rechargement du style, rotation, surzoom et limites mémoire. | `backend/app/api/routes/map_tiles.py`, `backend/app/application/services/map_query.py`, `mobile/lib/features/map/` ; `backend/tests/api/test_map_tiles.py`, `backend/tests/database/test_map_tile_cache.py`, `mobile/test/features/map/` ; [contrat NW-220](architecture/marine-zoom-persistence.md) |
| Signalement manuel / photo | Vérifier la confirmation du point final (longitude, latitude), les trois catégories et l'idempotence de `client_report_id` après réponse perdue. Pour le mode photo : estimation puis confirmation, publication, envoi JPEG distinct, nouvel essai sur le **même** signalement tant que le parcours reste ouvert, URL signée et nettoyage des objets orphelins. Fermer le parcours avant le succès : aucune reprise JPEG automatique ne doit être annoncée. | `backend/app/api/routes/reports.py`, `position_estimates.py`, `backend/app/application/services/create_report.py`, `upload_report_photo.py` ; `backend/tests/api/test_reports.py`, `test_photo_uploads.py`, `test_position_estimates.py` ; `mobile/test/features/reports/`, `camera/` |
| Alertes et notifications | Contrôler séparément préférence utilisateur et autorisation OS, appareil actif, dernière position, distance PostGIS de 10 NM, réévaluation par le worker et déduplication des alertes. Tester l'ouverture vers la carte en avant-plan, arrière-plan et démarrage à froid, avec et sans GPS ; ne jamais considérer les coordonnées FCM comme source de vérité. `sent` confirme l'acceptation FCM, non sa réception sur téléphone. L'historique GET /users/me/alerts concerne les **alertes reçues**, pas les signalements de l'auteur. | `backend/app/application/services/send_notifications.py`, `list_my_alerts.py`, `mobile/lib/core/notifications/`, `mobile/lib/features/alerts/` ; `backend/tests/database/test_notification_worker.py`, `backend/tests/api/test_my_alerts.py`, `mobile/test/features/alerts/` ; [ticket NW-163](https://linear.app/blueway/issue/NW-163/fix-nw-125-ouvrir-les-alertes-fcm-sur-la-carte-avec-cadrage-gps-et) |
| Administration et modération | Contrôler accès refusé aux non-administrateurs et comptes suspendus, session web, CSRF et séparation des pages HTML des opérations API. Vérifier motifs obligatoires, suppression/restauration d'un signalement, masquage de photo, suspension/réactivation de compte, traçabilité transactionnelle et impossibilité d'obtenir une **nouvelle** URL signée après masquage. | `backend/app/api/routes/admin.py`, `backend/app/web/routes/admin_pages.py`, `backend/app/application/services/moderation.py` ; `backend/tests/api/test_admin_moderation.py`, `test_admin_reads.py`, `test_admin_web.py`, `test_admin_web_pages.py` |
| Livraison et retour arrière | Contrôler la CI et les audits avant livraison, vérifier que les PR et le lancement manuel n'entraînent aucun déploiement, puis comparer le SHA déployé à GET /version. Sur un environnement autorisé, vérifier restauration applicative, sauvegardes, migrations et workers ; un worker démarré ne prouve pas la réception d'un push. Le workflow actuel déploie uniquement après push validé sur `dev`, sous réserve des accès et protections GitHub. | `.github/workflows/checks.yml`, `production.yml`, `deploy/hostinger/ci-deploy.sh`, `deploy/hostinger/deploy.sh` ; [procédure opérationnelle](../deploy/README.md) |

Les validations **Android**, **iOS**, **FCM distant**, **Scaleway réel** et **VPS**
doivent avoir leurs propres preuves horodatées. Ne pas convertir en réussite
de recette la présence d'un test, d'un fichier de code ou d'un rapport historique.

## Bilan de tests retenu pour le Stage 4

La référence de soutenance est le [rapport Preuves et résultats des tests du 29 octobre 2026](NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf), également présent dans le [Drive Stage 4](https://drive.google.com/drive/folders/1Oaq6JQChxLm8siO_6OPlh5odmq5J-vKW). Le [rapport de bug tracking](NoWave_Rapport_Bug_Tracking.pdf) documente les correctifs.

Les anciens rapports individuels, captures et journaux de `docs/test-reports/` ont été retirés de la branche de nettoyage. Ils restent récupérables dans l'historique Git. Le rapport Stage 4 synthétise les résultats, sans reprendre toutes les traces brutes et sans garantir des essais réels non documentés.
## Correspondance fonctionnelle, code et tests

La table suivante reprend les correspondances utiles de l'ancienne matrice de
traçabilité du MVP, construite à partir de **dev@6b54aa8 (19 octobre 2026)**.
Les chemins de code et de tests sont des **points d'entrée de lecture**,
et non la preuve d'une exécution réussie, de la couverture exhaustive d'un
parcours ni de sa validation sur téléphone. Pour les contrats actualisés, se
reporter à la [documentation Stage 4](https://docs.google.com/document/d/1Gez2BmfkdjTLyE9jkyf-U_QzJkUWQ9mu/edit).
La synthèse de tests du 29 octobre 2026 porte sur une révision distincte,
identifiée dans son propre rapport.

| Parcours | Tickets Linear | Implémentation à consulter | Tests à consulter |
| --- | --- | --- | --- |
| Inscription et profil | NW-51, NW-153, NW-155 | \`backend/app/api/routes/users.py\`, \`mobile/lib/features/auth/\`, \`mobile/lib/features/profile/\` | \`backend/tests/api/test_users.py\`, \`mobile/test/features/profile/\` |
| Préférences, bateau et installations | NW-116, NW-117 | \`backend/app/api/routes/devices.py\`, \`backend/app/api/routes/users.py\`, \`mobile/lib/features/profile/\` | \`backend/tests/api/test_devices.py\`, \`backend/tests/api/test_my_alerts.py\` |
| Carte et tuiles MVT de signalements | NW-111, NW-114 | \`backend/app/api/routes/map_tiles.py\`, \`backend/app/application/services/map_query.py\`, \`mobile/lib/features/map/\` | \`backend/tests/api/test_map_tiles.py\`, \`backend/tests/database/test_map_tile_cache.py\`, \`mobile/test/features/map/\` |
| Signalements manuels | NW-104 | \`backend/app/api/routes/reports.py\`, \`backend/app/application/services/create_report.py\`, \`mobile/lib/features/reports/\` | \`backend/tests/api/test_reports.py\`, \`mobile/test/features/reports/\` |
| Estimation photo et téléchargement JPEG | NW-109, NW-112 | \`backend/app/api/routes/position_estimates.py\`, \`backend/app/api/routes/reports.py\`, \`mobile/lib/features/camera/\` | \`backend/tests/api/test_photo_uploads.py\`, \`backend/tests/api/test_position_estimates.py\`, \`mobile/test/features/camera/\` |
| Historique des alertes | NW-125 | \`backend/app/api/routes/users.py\`, \`backend/app/application/services/list_my_alerts.py\`, \`mobile/lib/features/alerts/\` | \`backend/tests/api/test_my_alerts.py\`, \`mobile/test/features/alerts/\` |
| Alertes FCM et ouverture de la carte | NW-157, NW-163 | \`backend/app/application/services/send_notifications.py\`, \`mobile/lib/core/notifications/\`, \`mobile/lib/features/alerts/\` | \`backend/tests/database/test_notification_worker.py\`, \`mobile/test/features/alerts/\` |
| Administration et modération | NW-48 pour les données ; tickets de modération dans Linear | \`backend/app/api/routes/admin.py\`, \`backend/app/web/routes/admin_pages.py\`, \`backend/app/application/services/moderation.py\` | \`backend/tests/api/test_admin_moderation.py\`, \`backend/tests/api/test_admin_web.py\` |
| Sauvegarde et déploiement VPS | NW-57, NW-84 | \`.github/workflows/checks.yml\`, \`.github/workflows/production.yml\`, \`deploy/hostinger/\` | [Guide de déploiement](../deploy/README.md) et contrôles CI ci-dessus |
| Documentation et traçabilité | NW-83, NW-129, NW-166 à NW-170 | \`README.md\`, \`docs/README.md\`, \`docs/TESTING.md\`, \`docs/architecture/\` | [Documentation Stage 4](https://docs.google.com/document/d/1Gez2BmfkdjTLyE9jkyf-U_QzJkUWQ9mu/edit) et [bilan des tests](NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf) |

Les parcours de la carte marine ont évolué depuis cette première table :
les endpoints publics, les chargements GeoJSON, les seuils et la persistance
NW-220 sont détaillés dans [l'annexe marine](architecture/marine-zoom-persistence.md)
et dans la documentation Stage 4. Ne pas limiter cette partie aux anciennes
tuiles MVT des signalements.

### Exclusions et limites de périmètre du MVP

Les routes suivantes sont signalées comme **non implémentées** dans le contrat
Stage 4 de référence. Les vérifier de nouveau dans le code avant toute
annonce de disponibilité future.

| Fonction | Suivi | Précaution |
| --- | --- | --- |
| Modification d'un signalement par son auteur : \`PATCH /api/v1/reports/{report_id}\` | NW-73 | Ne pas la confondre avec les opérations administrateur |
| Suppression par l'auteur : \`DELETE /api/v1/reports/{report_id}\` | NW-73 | La suppression en modération a une route différente |
| Historique des signalements créés : \`GET /api/v1/users/me/reports\` | NW-74 | \`GET /users/me/alerts\` concerne les alertes reçues |
| Regroupement métier de signalements à 200 m | NW-75 | Distinguer la règle métier du regroupement visuel par zoom ; ne pas déduire son statut de la seule présence de clusters MVT |

### Informations minimales d'une nouvelle preuve

Pour chaque recette, conserver la **date et le fuseau**, le **SHA précis**,
le **ticket**, l'**environnement** (modèle d'appareil et version OS si applicable),
les **actions ou commandes**, le **résultat attendu**, le **résultat observé**,
la **référence du journal ou de la capture**, les **limites** et le
**responsable**. Un ticket Linear fermé, un fichier de test présent et une CI
réussie ne prouvent pas individuellement la réception de notifications ou
la validation des capteurs sur appareil réel.
