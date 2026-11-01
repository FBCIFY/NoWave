# Déploiement

Le VPS exécute le site, l’API, PostgreSQL/PostGIS et les workers dans Docker, derrière le tunnel Cloudflare.

## Prérequis

- VPS Linux avec Docker Compose et accès SSH `root` configuré pour la CI.
- `/opt/nowave/config/photo-storage.env` : `PHOTO_STORAGE_BUCKET` et `PHOTO_STORAGE_REGION` (`fr-par`, `nl-ams` ou `pl-waw`).
- `/opt/nowave/secrets/` : `tunnel_token`, `firebase_service_account.json`, `firebase_web_api_key`, `scaleway_access_key`, `scaleway_secret_key`.
- Compte de service Firebase du projet `blueway-dev`, avec les accès nécessaires à FCM.
- Bucket Scaleway privé, sans versioning ; clés autorisées à lire, écrire, supprimer et lister `reports/`.
- `MAPBOX_PUBLIC_TOKEN`, jeton public `pk.*` autorisé pour les domaines utilisés, à injecter dans l’API : le Compose de production ne le transmet pas par défaut.
- Volumes de base et `marine-cache` persistants ; garder les secrets hors Git.

Les fichiers attendus sont déclarés dans `compose.yaml` et `tunnel.yaml`. Le script de démarrage prépare les identifiants SQL ; il conserve les valeurs déjà présentes.

## Déployer

Dans l’environnement GitHub `production`, configurer :

- la variable `NOWAVE_DEPLOY_HOST` ;
- les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`.

Fusionner une PR dans `dev` lance la CI, les audits, puis le déploiement du même commit. Les PR et les lancements manuels ne déploient pas. `main` reçoit les releases stables après recette.

`hostinger/ci-deploy.sh` reconstruit et audite sur le VPS. `hostinger/deploy.sh` sauvegarde l’installation existante, applique les migrations et contrôle les services avant promotion. Les livraisons sont sérialisées.

En cas d’échec, le script remet l’application et le tunnel précédents ; sans version précédente, il arrête les nouveaux services. Les données SQL ne sont pas restaurées automatiquement. Les volumes et sauvegardes sont conservés ; une sauvegarde quotidienne est aussi prévue.

## Tests

```sh
curl --fail https://api.no-wave.fr/version
```

- Comparer `version` au commit livré et au workflow GitHub.
- Vérifier les logs des services `api`, `notifications` et `photo-cleanup`, puis les contrôles publics du déploiement.
- Sur téléphone, tester la carte, une publication avec photo et une alerte reçue sur un second appareil.
