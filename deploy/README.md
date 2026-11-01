# Livraison sur le VPS

Le site, l’API, PostgreSQL/PostGIS et les workers tournent dans Docker. Cloudflare Tunnel publie `no-wave.fr` et `api.no-wave.fr` ; PostgreSQL reste sur le réseau privé.

Seul un push sur `dev` peut déclencher une livraison, après réussite de la CI et des audits. Le VPS reçoit le commit testé. Les PR et les lancements manuels valident le code sans déployer ; `main` reçoit les releases stables après recette.

L’environnement GitHub `production` doit contenir `NOWAVE_DEPLOY_HOST`, `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`. Le premier est une variable ; les deux autres sont des secrets. La CI se connecte en SSH avec le compte `root`.

## Ce qui doit être présent sur le serveur

Le VPS demande Linux, Docker Compose et Python 3 pour les scripts de livraison. Garder les secrets dans `/opt/nowave/secrets`, les paramètres dans `/opt/nowave/config`, hors du dépôt.

- `tunnel_token` : jeton du tunnel Cloudflare dédié.
- `firebase_service_account.json` : compte de service du projet `blueway-dev`, autorisé à envoyer les notifications FCM.
- `firebase_web_api_key` : clé web Firebase pour la connexion admin.
- `scaleway_access_key` et `scaleway_secret_key` : accès au bucket photo privé, sans versioning. Autoriser lecture, écriture, suppression et listing de `reports/`.
- `photo-storage.env`, dans le dossier de configuration : `PHOTO_STORAGE_BUCKET` et `PHOTO_STORAGE_REGION`, parmi `fr-par`, `nl-ams`, `pl-waw`.

Injecter aussi `MAPBOX_PUBLIC_TOKEN` dans l’API pour la carte web : jeton public `pk.*` limité aux domaines utilisés. Le Compose de production ne le transmet pas par défaut.
Les fichiers attendus sont déclarés dans `compose.yaml` et `tunnel.yaml`. Le déploiement prépare les identifiants SQL et conserve les valeurs existantes. Les volumes de base et `marine-cache` restent persistants.

## Pendant la livraison

`hostinger/ci-deploy.sh` reconstruit et audite les images sur le VPS. `hostinger/deploy.sh` sauvegarde l’installation existante, applique les migrations, démarre les services, puis contrôle l’origine et les accès publics. Les livraisons sont sérialisées.

Si une étape échoue, le script remet l’application et le tunnel précédents. Sans version précédente, il arrête les nouveaux services. Il conserve volumes et sauvegardes ; les données SQL ne sont pas restaurées automatiquement. Une sauvegarde quotidienne complète celle faite avant livraison.

## Vérifier le résultat

Depuis le poste :

```sh
curl --fail https://api.no-wave.fr/version
```

Comparer `version` au commit livré et au résultat du workflow. Pour lire les logs sur le VPS, dans `/opt/nowave/config` :

```sh
docker compose --env-file release.env -f compose.yaml --profile api logs --tail=100 api notifications photo-cleanup
```

Vérifier ensuite sur téléphone la carte, une publication avec photo et une alerte sur un second appareil.
