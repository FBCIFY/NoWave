# NoWave

Application de signalements maritimes : obstacles, animaux marins et pollution. App Flutter, API FastAPI/PostGIS, carte Mapbox, authentification et notifications Firebase.

[Télécharger l’application mobile](https://no-wave.fr/downloads/mobile/).

Le compte de l’utilisateur désigné sera configuré en `admin` à sa création par le responsable du projet pour accéder à [l’administration](https://no-wave.fr/admin).

## Lancer le projet

Installer Docker avec Compose. Depuis la racine :

```sh
cp .env.example .env
# Compléter les variables et le chemin du compte de service Firebase.
docker compose up --build -d --wait
```

Site : [localhost:8443](https://localhost:8443). Accepter le certificat local. API : [localhost:8000/docs](http://localhost:8000/docs). Les migrations sont automatiques ; `docker compose down` arrête les services en conservant les données. Les secrets restent hors Git.

Workers locaux (alertes et nettoyage photo) :

```sh
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

## Documentation

| Besoin | Guide |
| --- | --- |
| Routes, entrées, réponses et erreurs | [Contrats API](docs/API.md) |
| Développer un composant | [Backend](backend/README.md) · [Mobile](mobile/README.md) · [Web](web/README.md) |
| Lancer les tests | [Tests](docs/TESTING.md) |
| Livrer et exploiter | [Déploiement](deploy/README.md) |
| Carte, sources et autres guides | [Index](docs/README.md) |

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).

NoWave ne remplace pas les informations nautiques officielles.
