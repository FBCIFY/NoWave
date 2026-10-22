# PR #125 — correction CI et sélection des preuves

Cette intervention corrige la sécurité des images Web et allège la revue. Le code cartographique, ses tests, ses verrous de dépendances, `marine-visual-7`, les couleurs, les zooms et les configurations de cache restent identiques au HEAD de référence.

## A. Audit Trivy

PR [#125](https://github.com/FBCIFY/NoWave/pull/125), source `fix/NW-220-coastal-raster-artifacts`, cible `dev`. Avant modification, HEAD local, distant et PR identiques : `f5e4527bd730dbda8ce6f716d941a32841f5f6f6`. Références distantes récupérées ; seuls `docs/design/` et `mobile/codex_photo/` étaient non suivis. Les sept empreintes protégées ont été vérifiées ; ces fichiers sont exclus du commit.

Le [run initial 39858816554](https://github.com/FBCIFY/NoWave/actions/runs/39858816554) utilise le merge de test `53baa0857b8695b38f8e6b61f3dfec58bb1d6426`, distinct du HEAD de branche. L'[artefact de production](https://github.com/FBCIFY/NoWave/actions/runs/39858816554/artifacts/12461352293) a été téléchargé et analysé : il contient `api.json` et `web.json`. Le scanner épinglé est **Trivy 0.73.0**, image `aquasec/trivy@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c`.

**Cause exacte :** l'image `nowave-web:53baa0857b8695b38f8e6b61f3dfec58bb1d6426`, identifiée Alpine **3.24.2** par Trivy, conserve le paquet **nginx 1.30.5-r1** de l'ancien digest officiel. Le simple `apk upgrade` déjà présent ne l'a pas remplacé par la version de sécurité. Le scan API a réussi ; le scan Web a produit six résultats actifs puis exit1. Le script s'arrêtant au premier échec, Postgres, tunnel et audit de configuration n'avaient pas encore été exécutés. Ce n'est pas une panne du scanner ou de sa base.

| Avis signalé dans l'artefact initial | Sévérité Trivy | Installé | Correctif indiqué par la base |
| --- | --- | --- | --- |
| CVE-2026-15176 | HIGH | nginx 1.30.5-r1 | 1.30.6-r0 |
| CVE-2026-93479 | HIGH | nginx 1.30.5-r1 | 1.30.6-r0 |
| CVE-2026-97205 | HIGH | nginx 1.30.5-r1 | 1.30.6-r0 |
| CVE-2026-90439 | MEDIUM | nginx 1.30.5-r1 | 1.30.6-r0 |
| CVE-2026-95101 | MEDIUM | nginx 1.30.5-r1 | 1.30.6-r0 |
| CVE-2026-97629 | MEDIUM | nginx 1.30.5-r1 | 1.30.6-r0 |

Les sévérités ci-dessus sont celles du contrôle CI et peuvent différer des classifications du fournisseur. Les [avis Nginx](https://nginx.org/en/security_advisories.html) annoncent notamment la branche corrigée 1.30.6 ; pour CVE-2026-90439, le fournisseur annonce déjà 1.30.5, alors que la base Alpine employée par Trivy exige 1.30.6-r0. Aucun résultat n'a été ignoré sur la base de cette divergence.

**Correction ciblée :** `deploy/web/Dockerfile` et le Dockerfile Web autonome `web/Dockerfile` utilisent désormais l'[image officielle stable](https://hub.docker.com/_/nginx) `nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951`, dont le manifeste amd64 est `sha256:84ed8c0dd296c188bfc24ed506f46589e9285fb0b11cf3a04d91d524d3067e11`. L'ancien digest de production était `sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94` ; le Dockerfile autonome utilisait auparavant le tag flottant `stable-alpine`.

L'image reconstruite contient **nginx 1.30.6-r1**, Alpine **3.24.3**, vérifiés par APK et par le rapport Trivy. La configuration Nginx n'est pas modifiée. Aucun seuil, exclusion de vulnérabilité, `exit-code`, VEX existant ou verrou de dépendance n'a changé. Les deux workflows et `build-and-audit.sh` restent strictement identiques.

**Nouveaux scans locaux :** API, Web, Postgres et tunnel reconstruits, chacun avec **0 vulnérabilité active**. Le VEX du tunnel reste celui déjà présent, sans nouvelle exclusion. Audit de configuration : **0 anomalie** sur les configurations analysées. Le script complet termine avec exit0 et crée son marqueur final de succès ; la base Trivy a été téléchargée depuis le miroir prévu par la CI. Rapports JSON conservés sous `test-results/containers/` (non versionnés), journaux locaux sous `/tmp/nowave-pr125-review/`.

## B. Nettoyage de la PR

- Avant : **294 fichiers** dans la PR, dont **272 preuves**, **26 350 439 octets** de preuves.
- Sélection : **43 preuves** ; **229 fichiers retirés**, représentant **19 760 851 octets** (18,85 Mio, environ75% du volume initial non compressé).
- Après : **69 fichiers** attendus au diff final contre la base commune de `dev`, dont43 preuves et deux nouveaux documents de synthèse/inventaire. Les tailles finales des README peuvent varier légèrement après leur mise à jour.

L'[inventaire de chaque fichier initial](NW-220-PR125-evidence-inventory.csv) fournit chemin, type, taille, SHA-256, rôle, utilité pour la revue, nécessité de reproduction et décision. Six groupes de doublons exacts ont été identifiés, notamment `tile-metrics.json`/`tiles/metrics.json` et les deux `counteraudit.json` ; les copies redondantes sont retirées.

Conservés : les deux rapports finaux antérieurs, les trois couples avant/après représentatifs, le pipeline côtier, les deux planches finales Android, l'attribution, les synthèses de mesures et de performance, les empreintes protégées, les scripts finaux et deux tuiles adjacentes avec source WMS, masque, résultat attendu et paramètres. Le [README final](artifacts/NW-220-gray-pixelation/README.md) guide la revue de Vadim et Brice et le rejeu hors réseau.

Retirés : captures intermédiaires ou individuelles déjà couvertes par les planches, séries de PNG dérivés, MVT historiques répétés, journaux temporaires et JUnit volumineux. Ce sont exclusivement des fichiers suivis ajoutés par la PR. Les originaux non suivis restent intacts. Les suppressions seront enregistrées par un commit normal, sans rebase ni force-push ; les preuves historiques complètes restent accessibles au SHA initial et via les commandes `git archive` documentées.

Les liens locaux retirés ont été remplacés par des liens immuables vers `f5e4527b`. Les rapports distinguent leur recette historique de la sélection actuelle. Les contrôles existants publient déjà logs, JUnit, couverture et Trivy comme artefacts GitHub Actions avec14 jours de rétention ; aucun changement de workflow n'est nécessaire. Les preuves durables restent dans Git et ne dépendent pas de cette rétention.

## C. Validations locales

| Vérification | Résultat |
| --- | --- |
| Suite backend complète avec PostGIS isolé | **1324 réussites, 2 ignorés, 0 échec/erreur**, 53,10s |
| Flutter, sortie machine avec couverture | **881 réussites, 0 échec, 0 ignoré**, 48,33s |
| Web, `node --test` | **10 réussites, 0 échec, 0 ignoré** |
| `flutter analyze --no-pub` | Aucun problème |
| `dart format --output=none --set-exit-if-changed lib test` |243 fichiers,0 modifié |
| Ruff backend/déploiement/outils mobiles | Réussi |
| Syntaxe de tous les scripts de déploiement | Réussie |
| Web : installation verrouillée, formatage, build Vite | Réussis |
| `npm audit --audit-level=low` |0 vulnérabilité |
| `pip-audit==2.10.1`, verrou de production avec hashes |0 vulnérabilité |
| Même audit, dépendances de tests verrouillées |0 vulnérabilité |
| Rejeu des deux tuiles adjacentes conservées |2/2 : pixels et couverture identiques, alpha borné par l'eau |
| Images production Web et API : health, accueil et readiness |4 requêtes HTTP200 |
| Web autonome : build, health et accueil | Réussis, HTTP200, nginx1.30.6 |
| Intégrité des sept fichiers protégés / liens locaux | Vérifiées |
| `git diff --check` | Réussi avant commit |

Commandes backend : projet Docker dédié `nowave-pr125-review`, `compose.test.yaml`, port55435, puis `NOWAVE_TEST_ADMIN_URL=postgresql://nowave_ci:ci-test-only@127.0.0.1:55435/nowave_ci .venv/bin/python -m pytest backend/tests -q --junitxml=/tmp/nowave-pr125-review/backend.xml`. Base et réseau éphémères, aucun volume utilisateur ni accès à la production.

Commande images : `bash deploy/hostinger/build-and-audit.sh f5e4527bd730dbda8ce6f716d941a32841f5f6f6` sur l'arbre corrigé. Ce tag local reprend le SHA de référence pour comparer les builds ; il ne prouve pas que l'image provient de l'ancien arbre Git. Seule la nouvelle CI contrôlera le nouveau SHA/merge exact après le push. Critères conservés : vulnérabilités **UNKNOWN, LOW, MEDIUM, HIGH, CRITICAL**, scanner `vuln`, **exit-code1**, puis audit de configuration.

Les deux skips backend sont préexistants : archive locale SHOM XYZ absente et sonde Nginx native optionnelle non activée. Nginx est ici compilé et testé en conteneur avec sa vraie configuration. Un avertissement Starlette/TestClient existant demeure. Les audits pip ont relu des entrées de cache non désérialisables puis ont terminé avec succès ; aucun résultat de vulnérabilité n'a été masqué.

Versions locales : Python3.14.4, Flutter3.47.6/Dart3.13.5 ; CI : Python3.12 et Flutter3.47.5. La CI distante reste nécessaire. Aucun nouveau parcours Android/iOS n'est revendiqué : la correction actuelle ne modifie aucun octet des sources ou tests cartographiques validés.

## D. Double review

Première passe technique : diagnostic indépendant des présomptions à partir des JSON et logs CI, contrôle des versions/digests, scans et tests applicatifs, démarrage effectif des images. Sélection des preuves basée sur leur rôle ; rejeu exact réussi après retrait des dérivés.

Seconde passe : reprise du diff complet contre la base commune de `origin/dev`, puis comparaison séparée avec `f5e4527b`. Aucun fichier applicatif/backend/Flutter ni test modifié ou supprimé ; seules les bases Nginx et la documentation/preuves changent dans cette intervention. Conservation vérifiée de `marine-visual-7`, couleurs, règles de zoom, budgets et fichiers de configuration. Les données des deux tuiles sélectionnées sont inchangées ; les43 fichiers retenus existent. Vérification des liens locaux après migration des liens historiques, des suppressions par rapport à l'inventaire et des empreintes protégées.

Ces deux passes sont réalisées successivement par le même intervenant avec des méthodes distinctes ; elles ne remplacent pas la validation humaine de Vadim et Brice. Les limites natives déjà documentées restent applicables. Aucun contrôle de sécurité ou test n'est affaibli.

## E. GitHub et verdict

Branche : `fix/NW-220-coastal-raster-artifacts`. PR [#125](https://github.com/FBCIFY/NoWave/pull/125). Reviewers initiaux `Chihaan` et `jidivici`, conservés. Aucun merge, changement direct de `dev`, déploiement Hostinger ou modification de secret.

Ce rapport est préparé avant le commit et le push de la correction. Le SHA publié, l'état de fusion et les résultats de chaque job distant seront vérifiés après le push et rapportés dans le compte rendu final et la description de la PR. La réussite locale ne vaut pas CI verte.

Verdict à ce stade : **PR non prête** tant que la nouvelle exécution GitHub Actions n'ont pas confirmé tous les contrôles. Le verdict final doit être fondé sur cette exécution, jamais sur les seuls résultats locaux.
