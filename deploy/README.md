# Déploiement de NoWave

Le VPS héberge le site web, l’API FastAPI et PostgreSQL/PostGIS dans des conteneurs Docker. Un tunnel Cloudflare dédié publie `no-wave.fr` et `api.no-wave.fr`. L’application mobile est construite séparément.

## Livraison

Le workflow **NoWave CI** (`.github/workflows/checks.yml`) exécute une seule fois
les contrôles Python, Flutter, PostGIS et web, dont le test HTTP du service Nginx
autonome. Après leur réussite, il appelle `.github/workflows/production.yml`
pour les audits des dépendances et des quatre images Docker. Un échec d'un
contrôle ou d'un audit bloque la livraison.

Après un push sur `dev`, un résultat valide déclenche le déploiement de cette
révision exacte sur le VPS. Les pull requests vers `dev` et `main` et les
lancements manuels exécutent seulement la validation. Pour une vérification
manuelle, lancer **NoWave CI** dans GitHub Actions ; `production.yml` est un
workflow appelé, sans déclencheur indépendant. Les livraisons sont sérialisées
et ne sont pas annulées par un nouveau push.

Le script `hostinger/ci-deploy.sh` reconstruit et audite les images sur le VPS, puis appelle `hostinger/deploy.sh`. Celui-ci effectue une sauvegarde, applique les migrations, démarre les services, vérifie l’origine privée, active le tunnel et vérifie les routes publiques. La révision courante n’est publiée qu’après réussite de l’ensemble de ces étapes.

Les rapports JSON d’audit sont conservés dans `test-results/containers`. La base
Trivy, son cache et les exports `.tar` des images sont temporaires : chaque export
est supprimé après son analyse et le répertoire de travail est nettoyé à la fin du
script, y compris en cas d’échec ou d’interruption SIGINT/SIGTERM. Un arrêt forcé
(SIGKILL) ou une panne du serveur peut laisser un répertoire `.audit-*` à nettoyer
après avoir vérifié qu’aucun audit ne l’utilise. Les images Docker restent disponibles
pour le déploiement et le retour arrière.

## Protection et sauvegardes

- L’API et PostgreSQL ne publient pas de port directement sur Internet.
- Les identifiants Firebase et le jeton Cloudflare restent dans `/opt/nowave/secrets`, hors du dépôt.
- `hostinger/backup.sh` sauvegarde la base et la configuration avant les mises à jour ; un timer système lance également une sauvegarde quotidienne sur le VPS.
- Chaque sauvegarde réserve un répertoire unique, même pour deux lancements dans la même seconde. `database.dump` n’apparaît qu’après validation du dump et copie de la configuration et des journaux ; un échec nettoie le répertoire incomplet.
- En cas d’échec des services, du tunnel ou des contrôles publics, `hostinger/deploy.sh` remet la précédente configuration applicative et celle du tunnel, puis redémarre le tunnel s’il fonctionnait auparavant. Sans version précédente, les nouveaux services applicatifs et le tunnel sont arrêtés. La base et ses sauvegardes sont préservées, sans restauration automatique des données. Un échec du rollback est explicitement signalé.

## Accès GitHub nécessaire

Pour que le déploiement automatique fonctionne, l’environnement GitHub `production` doit contenir la variable `NOWAVE_DEPLOY_HOST` et les secrets `NOWAVE_DEPLOY_SSH_KEY` et `NOWAVE_DEPLOY_KNOWN_HOSTS`. Ces accès ne sont pas fournis par le dépôt.

## Notifications de proximité

Le service `notifications` démarre avec le profil de production `api`, depuis
la même image et la même révision que l’API. Il utilise uniquement les secrets
PostgreSQL et Firebase existants et dispose d’un accès sortant à FCM. Le compte
Firebase doit être autorisé à envoyer des messages au projet `blueway-dev`.
Les secrets restent hors du dépôt. Aucun nouveau schéma ni migration ne sont requis.

Le déploiement vérifie que le conteneur exécute le worker attendu à la bonne
révision. Un échec déclenche le rollback ; les workers de la nouvelle version
sont arrêtés avant de restaurer les services de la version précédente. Ce contrôle
de processus ne prouve pas la disponibilité de FCM ni la réception sur téléphone.

Pour le diagnostic, consulter les logs du service `notifications` et les compteurs
de `nowave.notifications` par `status` et `last_error_code`, sans afficher de token.
Des tâches `pending` à zéro tentative avec un worker absent indiquent que l’envoi
n’a pas démarré, même si l’API est saine. Au démarrage, le worker reprend les tâches
committées, revérifie leur éligibilité et clôture les tâches expirées sans les envoyer.
`sent` signifie acceptation par FCM ; la réception doit être vérifiée sur un téléphone.

## Stockage photo NW-112

Avant la première livraison avec les photos, créer un bucket Scaleway privé
(sans versioning) et une clé dédiée autorisée à lister `reports/`, écrire, lire
et supprimer ses objets. Aucun accès public ni URL permanente n'est utilisé.
La signature S3 v4 suit la [documentation Scaleway](https://www.scaleway.com/en/docs/object-storage/concepts/).

Installer hors du dépôt :

- `/opt/nowave/config/photo-storage.env`, avec `PHOTO_STORAGE_BUCKET` et
  `PHOTO_STORAGE_REGION` (`fr-par`, `nl-ams` ou `pl-waw`).
- `/opt/nowave/secrets/scaleway_access_key` et
  `/opt/nowave/secrets/scaleway_secret_key`, contenant chacun uniquement la clé.

Le déploiement vérifie la présence de ces fichiers avant le remplacement des
services et protège les clés en `root:10001`, mode `0440`. La configuration du
bucket est indépendante de `release.env` et conservée dans les sauvegardes.
Les identifiants Firebase restent séparés. `NOWAVE_CONFIG_DIR` et
`NOWAVE_SECRETS_DIR` permettent de valider Compose avec des répertoires de test.

Le rôle `nowave_runtime` obtient `UPDATE` sur `report_photos` lors des migrations.
Les connexions PostgreSQL de l'API sont réutilisées dans un pool de 15 connexions maximum par
processus. Les refus nginx pour débit ou connexions répondent 429 ; une panne
de base répond 503. Le journal JSON du serveur web expose `status`,
`upstream_status`, `limit_req_status` et `limit_conn_status` pour distinguer
ces cas lors d'une recette de zooms répétés. Comparer aussi la révision de
`/version` avec la révision livrée avant d'attribuer un incident à ce réglage.
Les sept familles XYZ marines ont un budget distinct de **40 requêtes/s/IP**,
avec une rafale bornée à 128 et mise en attente au-delà de 16. La limite générale
reste à 10/s pour profil, publication et métadonnées ; les MVT de signalements
restent à 30/s. Les flux marins ont un plafond séparé de **64 requêtes
simultanées/IP** : un écran de neuf tuiles sur sept sources ne doit pas saturer
le plafond de 30 connexions/IP des autres routes. Le cache
marin persistant réduit les appels fournisseurs mais ne réduit pas le nombre
de requêtes reçues par Nginx : ces protections sont complémentaires.

La bathymétrie visuelle conserve également ses PNG terminés (couleurs et masque
côtier inclus) dans `MARINE_CACHE_DIR/bathymetry.sqlite3`, pendant 24 heures,
avec un plafond de 128 Mio sur disque et 32 Mio en mémoire. Le cache est
versionné avec le rendu côtier ; toute modification de couleurs ou de masque
doit changer cette version et celle de l'URL mobile. Les demandes simultanées
de la même tuile partagent un seul rendu. Au maximum huit rendus occupent les
workers, les autres attendent de façon asynchrone (file bornée à 128 tuiles).
Un échec n'est jamais enregistré comme un océan vide et aucun masque côtier
n'est contourné. Le cache disque natif mobile réutilise ces PNG publics selon
leur durée HTTP, sans modifier le cache des sondes numériques.

Pour reproduire sans charge publique, utiliser `backend/tools/probe_marine_rate_limits.py`
avec un binaire Nginx local. Ce scénario ne contacte que le loopback et un
fournisseur synthétique, après préchauffage du vrai cache `MarineHTTP`.
Le probe inclut deux écrans de 63 tuiles simultanées avec des réponses lentes
et vérifie l'accès au profil pendant leur chargement.
Les résultats locaux ne prouvent pas l'origine d'un 429 distant : vérifier
`limit_req_status` et `upstream_status` dans les logs de production. Les 429/503
amont conservent le backoff `Retry-After` du transport marin ; aucune boucle de
retries ni préchargement de zones n'est ajouté.

Le service `photo-cleanup` partage le code de l'API et tourne toutes les cinq
minutes ; ses logs indiquent les suppressions et les pannes sans exposer les
secrets ni les URL signées. Il ne supprime que les objets NoWave non référencés
âgés d'au moins une heure. La configuration Nginx accepte 512 000 octets sur la
route d'upload uniquement, enveloppe multipart comprise.

Recette avant validation de l'intégration réelle : envoyer un JPEG depuis Flutter,
répéter après réponse perdue, ouvrir son URL, vérifier son refus après cinq
minutes, masquer la photo et vérifier qu'aucune nouvelle URL n'est émise. Simuler
une panne de stockage puis confirmer que le même report_id peut être réessayé.
Vérifier les logs et la disparition d'un objet orphelin après le délai de nettoyage.
Utiliser un compte de recette ; aucune réussite de cette recette n'est implicite.

## Convention Git de déploiement - [FIX T15 (NW-168)](https://linear.app/blueway/issue/NW-168) (19/10/2026)

La branche `dev` est à la fois la **branche d'intégration** et, après les quatre contrôles CI ainsi que les audits requis, la source du **déploiement automatique actuel** sur le VPS. Le déploiement utilise le SHA précis du push validé. L'environnement GitHub portant le nom `production` ne constitue pas la preuve d'un deuxième serveur ou d'un environnement staging séparé.

La branche `main` est la **référence des releases stables**, promues par Pull Request depuis `dev` après QA. Dans les workflows en vigueur, un push sur `main` ne déclenche **pas** de déploiement autonome ; une PR vers `main` exécute uniquement la validation. Il faut donc distinguer :

- **code présent dans `dev`** : dernière intégration partagée ;
- **version réellement déployée** : SHA confirmé par `GET /version` et le workflow de livraison ;
- **release stable validée** : révision promue sur `main` après recette ;
- **réception mobile et FCM** : recette spécifique, non prouvée par un conteneur démarré.

Pour chaque livraison ou soutenance, noter la date, le SHA `dev`, le SHA annoncé par `/version`, le résultat du workflow GitHub Actions, la PR éventuelle `dev` vers `main` et les vérifications fonctionnelles réellement réalisées. Références : [parcours livraison](../docs/parcours/deploiement.md), [matrice de traçabilité](../docs/traceability-matrix.md), [CONTRIBUTING](../docs/CONTRIBUTING.md). Responsable : Brice (NW-57, NW-84).

### Livraison contrôlée des correctifs cartographiques

Le job de production est **désactivé par défaut**, y compris après un push sur
`dev`. Pour autoriser délibérément une livraison, définir la variable
GitHub Actions du dépôt `NOWAVE_PRODUCTION_DEPLOY_ENABLED=true`, seulement
après revue du commit et préparation de la fenêtre de déploiement. La retirer
ou la remettre à `false` après la livraison. Les validations des PR restent
actives même lorsque cette variable est absente.

Le workflow `.github/workflows/production.yml` vérifie cette variable avant
de commencer le job de déploiement. Les règles de protection de l'environnement
GitHub `production` (approbateurs, délais, restrictions de branches) doivent
aussi être contrôlées dans les paramètres GitHub ; le code source ne permet pas
d'établir leur configuration effective.

La vérification publique `deploy/hostinger/verify-public.sh` sonde une fois
par tentative trois tuiles marines représentatives près de Toulon :
`seamarks/12/2115/1503.pbf`,
`soundings/12/2115/1503.pbf` et
`bathymetry/12/2115/1503.png`. Les réponses HTTP 429/503, autres erreurs
non-2xx et délais dépassés empêchent la validation et déclenchent le rollback
prévu par `deploy.sh`. Cette vérification à faible débit ne prouve pas la
couverture complète des sept familles ni leur rendu Android ; conserver la
recette cartographique sur téléphone après livraison. Les erreurs de fournisseur
peuvent également bloquer la promotion, volontairement.
