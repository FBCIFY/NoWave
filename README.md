# NoWave

NoWave permet de signaler des obstacles, des animaux marins et de la pollution. L’app mobile affiche les observations sur une carte et envoie des alertes de proximité.

## Télécharger l’application

[Télécharger NoWave pour mobile](https://no-wave.fr/downloads/mobile/).

À la création du profil, le responsable du projet attribuera le rôle `admin` au compte de l’utilisateur désigné. Ce compte aura ainsi accès à [l’administration](https://no-wave.fr/admin).

## Stack

| Dossier | Contenu |
| --- | --- |
| `mobile/` | App Flutter/Dart, carte Mapbox, Firebase Auth et notifications FCM |
| `backend/` | API FastAPI, règles métier, PostgreSQL/PostGIS et stockage photo Scaleway |
| `web/` | Site public, carte des observations, build Vite et service Nginx |
| `deploy/` | Images Docker, scripts VPS et tunnel Cloudflare |
| `docs/` | Guides techniques, tests et bilans PDF |

L’API sert les signalements en tuiles MVT et les couches marines en GeoJSON. Mapbox fournit le fond de carte.

## Lancer en local

Prérequis : Docker avec Compose. Pour travailler sur chaque composant : Python 3.12, Flutter 3.47.5 et Node.js 24.

```sh
cp .env.example .env
# Renseigner les secrets et le chemin du fichier Firebase dans .env.
docker compose up --build -d --wait
curl --fail http://127.0.0.1:8000/health
```

- Site : [localhost:8443](https://localhost:8443).
- Admin : [localhost:8443/admin](https://localhost:8443/admin).
- API : [localhost:8000/docs](http://localhost:8000/docs).

Le certificat HTTPS local est généré au démarrage ; accepter ce certificat dans le navigateur. Les migrations sont automatiques. Les données restent dans le volume `nowave-database`. `docker compose down` arrête les services en conservant ce volume.

L’inscription standard crée un profil `user`. Le compte admin désigné demande l’attribution du rôle côté base de données. Le compte doit aussi avoir un e-mail Firebase vérifié et un profil actif.

Les ports se règlent dans `.env`. Ne pas committer les secrets ou les fichiers de compte de service Firebase.

## Guides

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).

- [Documentation](docs/README.md)
- [Backend et API](backend/README.md)
- [Installation mobile](mobile/README.md)
- [Site web](web/README.md)
- [Tests](docs/TESTING.md)
- [Contribution](docs/CONTRIBUTING.md)
- [Déploiement](deploy/README.md)

Les PR vont vers `dev`. La CI valide les tests et les audits ; un push validé sur `dev` déclenche le déploiement VPS. `main` reçoit les releases après recette.

Les signalements expirent après 24 h côté serveur. Leur retrait visuel dépend aussi du cache et du rafraîchissement de la carte. NoWave complète les informations nautiques officielles et ne les remplace pas.
