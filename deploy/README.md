# Déployer NoWave

Le VPS héberge Nginx, l'API FastAPI, PostgreSQL/PostGIS et les workers dans Docker.
Un tunnel Cloudflare publie `no-wave.fr` et `api.no-wave.fr`.
L'application mobile est construite séparément.

## Livraison automatique

Un push sur `dev` lance **NoWave CI** : Python, Flutter, PostGIS, Web et Admin Web.
Après réussite, `production.yml` audite les dépendances et les quatre images,
puis déploie la révision exacte du push. Les PR vers `dev` ou `main` et les
lancements manuels valident le code sans déployer. `main` reçoit les versions
stables par PR depuis `dev` après recette.

`hostinger/ci-deploy.sh` reconstruit et audite sur le VPS.
`hostinger/deploy.sh` sauvegarde, migre la base, démarre les services, vérifie
l'origine privée, active le tunnel puis vérifie les routes publiques.
La nouvelle révision n'est déclarée courante qu'après réussite complète.
Les livraisons sont sérialisées.

L'environnement GitHub `production` doit contenir :

- la variable `NOWAVE_DEPLOY_HOST` ;
- les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`.

Les protections et approbateurs de cet environnement se règlent sur GitHub.
Il n'existe pas de verrou `NOWAVE_PRODUCTION_DEPLOY_ENABLED` dans le workflow.
Pour confirmer une livraison, comparer `/version`, le SHA du push et le résultat
GitHub Actions, puis effectuer la recette fonctionnelle.

## Secrets et accès réseau

L'API et PostgreSQL n'exposent aucun port directement sur Internet. Les clés
restent dans `/opt/nowave/secrets`, hors du dépôt. Le service Firebase doit
correspondre au projet `blueway-dev` et permettre les envois FCM.
La connexion admin utilise le secret `firebase_web_api_key`.

Pour les cartes web, injecter `MAPBOX_PUBLIC_TOKEN` dans l'API avec un jeton
public `pk.*` limité aux domaines autorisés. Cette variable n'est pas fournie
par le Compose de production.

Pour les photos, créer un bucket Scaleway privé sans versioning et une clé
limitée à la lecture, l'écriture, la suppression et au listing de `reports/`.
Installer :

| Fichier | Contenu |
| --- | --- |
| `/opt/nowave/config/photo-storage.env` | `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION` (`fr-par`, `nl-ams` ou `pl-waw`) |
| `/opt/nowave/secrets/scaleway_access_key` | Clé d'accès |
| `/opt/nowave/secrets/scaleway_secret_key` | Clé secrète |

Le déploiement vérifie ces fichiers et protège les clés en `root:10001`, mode
`0440`. Les migrations appliquent les droits du rôle `nowave_runtime`.
`NOWAVE_CONFIG_DIR` et `NOWAVE_SECRETS_DIR` permettent de valider Compose avec
des répertoires de test.

## Sauvegardes et retour arrière

`hostinger/backup.sh` sauvegarde la base et la configuration avant chaque
livraison ; un timer lance aussi une sauvegarde quotidienne. Chaque sauvegarde
utilise un répertoire unique. Le dump définitif n'apparaît qu'après validation ;
un échec nettoie la sauvegarde incomplète.

Si les services, le tunnel ou les vérifications publiques échouent, le script
restaure la configuration applicative et celle du tunnel précédentes. Sans
version précédente, il arrête les nouveaux services. La base et les sauvegardes
sont préservées ; les données ne sont jamais restaurées automatiquement.
Un échec du rollback est signalé.

Les rapports d'audit restent dans `test-results/containers`. Les exports d'images
et caches Trivy temporaires sont nettoyés après chaque audit. Après un arrêt
forcé, vérifier qu'aucun audit ne tourne avant de nettoyer un répertoire `.audit-*`.
Les images de rollback sont conservées. Le timer `nowave-build-cache.timer`
borne le cache BuildKit récupérable à 4 Go, sous le verrou de déploiement, sans
effacer les volumes, sauvegardes ou images conservées.

## Workers

`notifications` et `photo-cleanup` utilisent la même image et la même révision
que l'API. Le déploiement vérifie le processus du worker FCM avant promotion.

- `notifications` reprend les tâches committées et vérifie encore leur
  éligibilité. Consulter ses logs et les compteurs SQL `status` / `last_error_code`
  sans afficher les tokens. `sent` signifie acceptation FCM ; vérifier la
  réception sur téléphone.
- `photo-cleanup` passe toutes les cinq minutes et supprime uniquement les
  objets NoWave non référencés depuis au moins une heure.

## Cartographie et limites réseau

Nginx répond `429` sur dépassement de débit ou de connexions. Une panne SQL donne
`503`. Ses logs exposent `status`, `upstream_status`, `limit_req_status` et
`limit_conn_status` pour distinguer les causes.

| Flux | Débit par IP | Rafale | Requêtes simultanées par IP |
| --- | --- | --- | --- |
| Routes générales | 10/s | 30, sans attente | 30 |
| MVT des signalements | 60/s | 128, attente au-delà de 15 | 128 |
| Sept familles XYZ marines | 120/s | 256, attente au-delà de 64 | 256 |

Le pool SQL est limité à 15 connexions par processus. L'API est plafonnée à
1,5 vCPU, 768 Mio et 384 requêtes entrantes simultanées.
Les uploads seuls acceptent 512 000 octets, enveloppe multipart comprise.

Le cache marin persistant réduit les appels fournisseurs. Les PNG bathymétriques
terminés sont conservés 24 h, avec 128 Mio sur disque et 32 Mio en mémoire.
Huit rendus peuvent tourner en parallèle ; la file est bornée à 128 tuiles.
L'attente d'un worker est limitée à 8 s et la réponse à 24 s, avant les 30 s Nginx.
Une erreur ne doit jamais être mise en cache comme une tuile vide.
Changer le masque ou les couleurs exige une nouvelle version de cache et d'URL.
La rétention OSM reste d'au moins sept jours ; un cache plein refuse les nouvelles
entrées au lieu d'effacer trop tôt les anciennes.

Le fond [GEBCO](marine/README.md) est servi directement par Nginx, avec un budget
séparé et un an de cache. EMODnet fournit le détail régional dans son emprise.
Pour reproduire les limites localement, utiliser
`backend/tools/probe_marine_rate_limits.py` : il contacte uniquement le loopback
avec un fournisseur de test.

## Recette après livraison

`hostinger/verify-public.sh` vérifie notamment trois tuiles près de Toulon :
`seamarks/12/2115/1503.pbf`, `soundings/12/2115/1503.pbf` et
`bathymetry/12/2115/1503.png`. Une erreur HTTP ou un délai dépassé bloque la
promotion et déclenche le rollback. Ce contrôle ne valide pas le rendu mobile.

Avec un compte et des données de recette :

1. Contrôler la carte sur téléphone, les déplacements et les couches marines.
2. Publier un signalement et vérifier une alerte sur un second appareil.
3. Envoyer un JPEG, répéter le même upload et ouvrir sa photo.
4. Vérifier l'expiration de l'URL après cinq minutes, puis masquer la photo et
   confirmer qu'aucune nouvelle URL n'est émise.
5. Tester une panne de stockage et la reprise sur le même signalement ; vérifier
   le nettoyage d'un objet orphelin après le délai prévu.

Les [commandes de test](../docs/TESTING.md) complètent cette recette.
