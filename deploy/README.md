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

## Accès GitHub nécessaire

Pour que le déploiement automatique fonctionne, l’environnement GitHub `production` doit contenir la variable `NOWAVE_DEPLOY_HOST` et les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`. Ces accès ne sont pas fournis par le dépôt.
