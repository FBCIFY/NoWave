# NoWave sur le VPS Hostinger

Cette configuration déploie le site `web`, l’API FastAPI et PostgreSQL 17/PostGIS. Le client mobile se construit séparément ; il n’est pas un service à lancer sur le VPS.

## Principes repris de Labelscan

- Révision Git exacte, images identifiées par cette révision, bases Docker épinglées par digest et dépendances Python avec empreintes.
- Tests web/API/base, migrations dans une base temporaire, audit npm et pip, audit Trivy de **toutes** les sévérités. Une vulnérabilité active bloque la livraison.
- Utilisateurs non root, systèmes de fichiers en lecture seule, capacités supprimées, `no-new-privileges`, limites CPU/mémoire/processus, contrôles de santé et rotation des journaux.
- Aucun port public pour l’API ou PostgreSQL. Données et mots de passe entièrement séparés de Labelscan.
- Rôle propriétaire réservé aux migrations ; l’API dispose d’un rôle PostgreSQL limité aux tables nécessaires. Firebase est vérifié au démarrage.
- Sauvegarde privée avant mise à jour ; conservation des journaux avant remplacement. Retour à l’image précédente en cas d’échec, sans restauration automatique destructive de données.
- Journalisation JSON sans corps, cookies, autorisations ni query strings ; en-têtes de sécurité, taille de requête limitée, limites de débit, vérification du domaine et de l’origine.

Le domaine prévu est `no-wave.fr`, avec `www.no-wave.fr` redirigé vers celui-ci et `api.no-wave.fr` pour le client mobile. L’API est également disponible sous `/api/v1` sur le domaine principal.

## Coexistence avec Labelscan

Labelscan conserve son Caddy, ses ports 80/443, ses réseaux, son pare-feu et ses déploiements. NoWave utilise un **tunnel Cloudflare dédié** qui établit uniquement des connexions sortantes chiffrées. Cette différence évite de redémarrer ou modifier le proxy Labelscan. Le serveur web NoWave est accessible pour les vérifications locales sur `127.0.0.1:18080`, jamais sur une interface publique.

Les réseaux `frontend` et `backend` sont internes. Seuls l’API (Firebase), le connecteur et le réseau de contrôle local disposent d’une sortie. L’adresse `172.30.72.2` est réservée au connecteur ; lui seul peut fournir `CF-Connecting-IP` au proxy. Vérifier que le sous-réseau `172.30.72.0/29` n’est pas utilisé avant la première installation.

## Secrets, hors Git

Le script `hostinger/bootstrap.py` crée une seule fois les répertoires privés et les mots de passe aléatoires sous `/opt/nowave/secrets`. Il ne remplace pas de valeur existante.

À installer séparément :

- `firebase_service_account.json` : compte de service existant du projet **blueway-dev**, mode `0440`, groupe `10001`.
- `tunnel_token` : jeton du seul tunnel NoWave, mode `0440`, groupe `65532`.

Ne pas utiliser le projet erroné `blueway-deve`, les identifiants utilisateur ADC ou les secrets de Labelscan. Ne jamais placer une clé dans une variable `VITE_*`, l’image Docker, un journal ou un commit. La landing page garde son formulaire de démonstration explicite : elle n’envoie pas de signalement réel.

## Installation / mise à jour

1. Exécuter les contrôles du workflow `Production validation` sur la révision exacte.
2. Transférer l’archive de cette révision vers `/opt/nowave/releases/<SHA>`. Seuls les fichiers suivis par Git sont inclus.
3. Depuis cette archive, lancer `bash deploy/hostinger/build-and-audit.sh <SHA>`. Le marqueur de réussite contient la révision ; conserver les rapports JSON d’audit.
4. Installer le compte de service privé, puis lancer `bash deploy/hostinger/deploy.sh <SHA>`. Le script sauvegarde, applique les migrations, démarre les conteneurs et vérifie les routes privées.
5. Configurer les noms publics du tunnel vers `http://web:8080` : `no-wave.fr`, `www.no-wave.fr`, `api.no-wave.fr`, puis une règle finale `http_status:404`. Ne pas exposer l’interface de mesures `2000` ni PostgreSQL.
6. Copier `deploy/tunnel.yaml` dans `/opt/nowave/config/`, puis activer le connecteur avec la même révision :

```sh
cd /opt/nowave/config
docker compose --env-file release.env -f compose.yaml -f tunnel.yaml --profile api up -d --wait tunnel
```

7. Dans Cloudflare : conserver les enregistrements mail existants lors de l’import DNS, activer HTTPS forcé et TLS minimum 1.2, conserver les protections WAF du plan et éviter les challenges navigateur sur les routes API mobiles. Vérifier le domaine depuis Internet avant d’annoncer la publication.

Aucun abonnement ni transfert de domaine n’est requis. Le changement des serveurs DNS doit intervenir seulement après copie complète des enregistrements actuels, notamment MX, SPF, DKIM et DMARC.

## Vérifications

```sh
bash deploy/hostinger/verify.sh http://127.0.0.1:18080 <SHA>
curl --fail https://no-wave.fr/version.json
curl --fail https://api.no-wave.fr/health/ready
```

Vérifier aussi : HTTPS valide, une seule occurrence des en-têtes de sécurité, refus des domaines inconnus, jetons absents/faux refusés, DB/API sans port publié, ressources et version de Labelscan inchangées, images et parcours lisibles sur mobile.

Les vérifications de refus d’authentification ne remplacent pas un test avec un utilisateur Firebase de test et son jeton valide. Ne jamais utiliser un compte réel pour des écritures/suppressions de recette non demandées.

## Sauvegardes et retour arrière

`hostinger/backup.sh` écrit un dump PostgreSQL et les configurations/journaux privés dans un répertoire daté. Il vérifie la lisibilité du dump. Avant usage réel, planifier ce script quotidiennement et copier les sauvegardes vers un stockage **hors VPS** avec un compte dédié ; cette destination doit être fournie et une restauration testée. Une sauvegarde uniquement locale n’est pas une sauvegarde hors site.

Le script de déploiement remet l’ancienne configuration API/web en cas d’échec, mais ne descend pas automatiquement les migrations et n’écrase pas la base. Toute migration incompatible nécessite une procédure de restauration examinée avant livraison. Pour une première installation sans ancienne version, un échec laisse les services privés et les journaux accessibles au diagnostic.

## Exceptions d’audit documentées

L’image standard Cloudflare contenait des bibliothèques système vulnérables. `tunnel/Dockerfile` reconstruit la version officielle 2026.9.3 à partir de son SHA, met à jour `golang.org/x/crypto` et utilise une base Alpine mise à jour. Le build échoue si le package OpenPGP concerné par `GO-2026-5932` est lié. Le fichier VEX ne couvre que ce code absent, selon la même méthode que Labelscan ; il ne masque pas les autres vulnérabilités.

Références : [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/get-started/), [paramètres du connecteur](https://developers.cloudflare.com/tunnel/reference/run-parameters/), [Firebase Admin](https://firebase.google.com/docs/admin/setup).
