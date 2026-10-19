# NoWave — Signalements maritimes géolocalisés

NoWave est un MVP de signalements participatifs pour la navigation de plaisance : **obstacles**, **animaux marins** et **pollution**. L'application mobile permet de publier une observation localisée, de consulter les signalements actifs sur une carte et de recevoir des alertes de proximité selon les préférences et la position du téléphone.

> **État documentaire :** le présent README décrit le code de `dev` au commit de référence [`6b54aa8`](https://github.com/FBCIFY/NoWave/commit/6b54aa861e5cda93bf9b573c443f5946d230945d), vérifié le 19/10/2026. Il ne constitue pas une preuve de recette sur appareil ni de disponibilité des services externes. Un signalement NoWave ne remplace pas les informations nautiques officielles.

## Architecture

| Composant | Implémentation | Rôle |
| --- | --- | --- |
| Application mobile | Flutter / Dart, Mapbox SDK, Firebase Auth/FCM | Écrans, capteurs, carte, signalements et alertes |
| API | Python / FastAPI, architecture ports/adaptateurs | Contrats HTTP, règles métier, authentification et orchestration |
| Base de données | PostgreSQL 17 / PostGIS | Signalements, géométrie, positions et historique d'alertes |
| Photos | Scaleway Object Storage privé | JPEG validés, lecture via URL temporaire |
| Administration | FastAPI / Jinja, sessions et CSRF | Modération et suivi administratif |
| Site de présentation | `web/` (Node.js à la compilation, Nginx au service) | Présentation du projet, indépendante de l'API |
| Livraison | GitHub Actions, Docker, VPS Hostinger et Cloudflare | Tests, audits et déploiement après push validé sur `dev` |

Les tuiles cartographiques **MVT** sont produites par le backend à partir de PostGIS, séparément du fond de carte rendu par Mapbox. Elles ne sont pas une base mondiale stockée sur le téléphone.

## Répertoires

```text
backend/          API FastAPI, domaine, infrastructure et tests
mobile/           Application Flutter et tests widget/unitaires
web/              Site de présentation autonome
deploy/           Docker, scripts VPS et documentation de déploiement
docs/             Index documentaire, parcours, tests et traçabilité
.github/workflows/  CI et validation de livraison
compose.yaml      Services de développement
compose.test.yaml Base PostGIS isolée pour les tests
```

## Démarrer en développement

**Prérequis :** Docker + Compose, Python 3.12 pour les tests, Flutter 3.47.5 pour le mobile ; Node.js 24 pour les contrôles web. Les clés Firebase/Scaleway et les paramètres cartographiques nécessaires sont à fournir séparément. Ne jamais committer `.env`, `.env.json` ni des clés privées.

Depuis la racine :

```sh
cp .env.example .env
# Renseigner les variables et secrets nécessaires dans .env et les fichiers référencés.
docker compose up --build -d database backend
curl --fail http://127.0.0.1:8000/health
```

Pour le mobile, suivre [mobile/README.md](mobile/README.md) : créer `mobile/.env.json` depuis l'exemple, puis `flutter run -d <device-id> --dart-define-from-file=.env.json`. Le site web peut être lancé indépendamment via [web/README.md](web/README.md).

## Routes et périmètre MVP

Les routes métier FastAPI se trouvent sous `/api/v1` ; `/health`, `/health/ready` et `/version` sont à la racine. La référence de `dev` comporte **28 opérations HTTP déclarées**, hors pages HTML d'administration. Voir le chapitre « Index des routes API » de la [documentation technique](https://docs.google.com/document/d/1PbbCySYhRy8_aeU4T19nfPSq3dXU-QI9/edit).

Les opérations `PATCH /api/v1/reports/{report_id}`, `DELETE /api/v1/reports/{report_id}` par l'auteur et `GET /api/v1/users/me/reports` **ne sont pas implémentées** dans cette référence et ne doivent pas être considérées comme disponibles. Le suivi de ces demandes reste dans Linear (NW-73 et NW-74). L'historique des **alertes reçues**, lui, est exposé par `GET /api/v1/users/me/alerts`.

La validité des signalements est de 24 h côté serveur. Les MVT ont un cache HTTP privé de 15 s ; la disparition à l'écran dépend également du rafraîchissement du mobile. Voir [parcours cartographique](docs/parcours/cartographie.md) (CON-024, option A).

## Tests et documentation

- [Index documentaire et parcours](docs/README.md)
- [Matrice de traçabilité, statut réel des preuves](docs/traceability-matrix.md)
- [Commandes de test, CI et limites de validation](docs/TESTING.md)
- [Règles de contribution et branches](docs/CONTRIBUTING.md)
- [Exploitation VPS et déploiement](deploy/README.md)

Les tests automatisés de l'interface ne prouvent pas à eux seuls la réception des notifications sur appareil, les capteurs physiques, la connexion aux services externes ou une recette complète du VPS. La matrice sépare ces niveaux de vérification.

**Gestion des branches :** PR depuis une branche de travail vers `dev` après revue ; une validation réussie du push sur `dev` déclenche le déploiement actuel sur VPS. `main` reste la référence de release stable après QA et PR `dev` → `main` ; aucun déploiement autonome depuis `main` n'est décrit dans le workflow actuel (CON-026, option A).