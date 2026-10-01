# Déploiement de NoWave

Le VPS héberge le site web, l’API FastAPI et PostgreSQL/PostGIS dans des conteneurs Docker. Un tunnel Cloudflare dédié publie `no-wave.fr` et `api.no-wave.fr`. L’application mobile est construite séparément.

## Livraison

Le workflow `.github/workflows/production.yml` exécute les tests web, API et base de données, puis les audits des dépendances et des quatre images Docker. Après un push sur `dev`, un résultat valide déclenche le déploiement de cette révision exacte sur le VPS. Les pull requests et les lancements manuels exécutent seulement la validation.

Le script `hostinger/ci-deploy.sh` reconstruit et audite les images sur le VPS, puis appelle `hostinger/deploy.sh`. Celui-ci effectue une sauvegarde, applique les migrations, démarre les services et vérifie la version sur l’adresse privée. Le tunnel est ensuite mis à jour et les routes publiques sont vérifiées.

## Protection et sauvegardes

- L’API et PostgreSQL ne publient pas de port directement sur Internet.
- Les identifiants Firebase et le jeton Cloudflare restent dans `/opt/nowave/secrets`, hors du dépôt.
- `hostinger/backup.sh` sauvegarde la base et la configuration avant les mises à jour ; un timer système lance également une sauvegarde quotidienne sur le VPS.
- En cas d’échec pendant le déploiement des services, `hostinger/deploy.sh` remet la précédente configuration applicative. Il ne restaure pas automatiquement la base de données.

## Schéma PostgreSQL NoWave

La base `nowave` utilise le schéma applicatif `nowave` : `nowave.users`,
`nowave.reports` et les huit autres tables. La migration initiale
`20260917_0001` crée directement ce schéma, avec l’index spatial
`reports_final_position_geometry_gist` utilisé par les tuiles. Une base existante
doit recevoir cet index séparément ; la migration initiale ne doit pas être
rejouée en production. Le projet Firebase reste `blueway-dev`.

Une remise à zéro est une opération distincte, jamais exécutée par la CI.
Après sauvegarde vérifiée et arrêt de l’API, un opérateur peut lancer, avec les
identifiants du propriétaire de la base, `python -m
app.infrastructure.database.reset_schema --confirm-drop-blueway
--expected-revision 20260920_0002`. Cette commande détruit les données du schéma
`blueway` et recrée les dix tables vides sous `nowave`, avec les droits du rôle
API. L’opération complète est transactionnelle et refuse une autre base, un
autre état de schéma ou une révision inattendue. Redémarrer ensuite l’API qui
utilise `nowave`, puis vérifier les routes et une écriture suivie de rollback.

## Accès GitHub nécessaire

Pour que le déploiement automatique fonctionne, l’environnement GitHub `production` doit contenir la variable `NOWAVE_DEPLOY_HOST` et les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`. Ces accès ne sont pas fournis par le dépôt.
