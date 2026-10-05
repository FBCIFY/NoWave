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
