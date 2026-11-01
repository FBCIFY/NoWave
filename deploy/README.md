# Déploiement et exploitation

Le VPS exécute Nginx, FastAPI, PostgreSQL/PostGIS et les workers dans Docker. Le tunnel Cloudflare expose `no-wave.fr` et `api.no-wave.fr` ; la base reste privée.

## Livraison

Un push sur `dev` déploie le même commit sur le VPS après réussite de la CI et des audits. Les PR et les lancements manuels ne déploient pas. `main` reçoit les releases stables après recette.

Dans l’environnement GitHub `production`, configurer :

- la variable `NOWAVE_DEPLOY_HOST` ;
- les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`.

`hostinger/ci-deploy.sh` construit et audite les images. `hostinger/deploy.sh` sauvegarde, applique les migrations, démarre les services et vérifie l’origine puis les accès publics. Les livraisons sont sérialisées ; un échec empêche la promotion du commit.

## Configuration VPS

Les secrets restent dans `/opt/nowave/secrets` et les paramètres dans `/opt/nowave/config`, hors Git. Les fichiers attendus sont déclarés dans `compose.yaml` et `tunnel.yaml`.

- Cloudflare : secret `tunnel_token` du tunnel dédié.
- Firebase : compte de service du projet `blueway-dev`, autorisations FCM et secret `firebase_web_api_key` pour l’admin.
- Carte web : `MAPBOX_PUBLIC_TOKEN`, jeton public `pk.*` autorisé pour les domaines utilisés, à injecter dans l’API.
- Photos : bucket Scaleway privé sans versioning, `photo-storage.env` avec `PHOTO_STORAGE_BUCKET` et `PHOTO_STORAGE_REGION`, secrets `scaleway_access_key` et `scaleway_secret_key`.
- Données marines : volume persistant `marine-cache` et fond [GEBCO](marine/README.md) inclus dans l’image web.

Le Compose de production ne transmet pas `MAPBOX_PUBLIC_TOKEN` par défaut. Les clés Scaleway doivent autoriser lecture, écriture, suppression et listing du préfixe `reports/`.

## Sauvegarde et retour arrière

`hostinger/backup.sh` sauvegarde la base et la configuration avant chaque livraison ; un timer réalise aussi une sauvegarde quotidienne.

Si la livraison échoue, le script restaure la version applicative et le tunnel précédents. Sans version précédente, il arrête les nouveaux services. Les données SQL ne sont pas restaurées automatiquement ; volumes et sauvegardes sont conservés.

## Vérifier une livraison

1. Comparer le SHA de `/version` au commit livré et contrôler le workflow.
2. Vérifier les logs de l’API, de `notifications` et de `photo-cleanup`.
3. Tester sur téléphone la carte, une publication avec photo et une alerte sur un second appareil.

`hostinger/verify-public.sh` contrôle les routes et des tuiles publiques avant promotion. Les rapports d’audit sont dans `test-results/containers`.

Pour diagnostiquer les accès : Nginx renvoie `429` sur dépassement de débit ou de connexions ; une dépendance indisponible peut donner `503`. Les logs incluent `upstream_status`, `limit_req_status` et `limit_conn_status`. Les seuils actifs sont dans `web/nginx.conf` et les limites de conteneurs dans `compose.yaml`.
