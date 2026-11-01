# NoWave

App de signalements maritimes : obstacles, animaux marins et pollution. Stack : Flutter, FastAPI, PostGIS, Firebase et Mapbox.

[Télécharger l’app mobile](https://no-wave.fr/downloads/mobile/).

Le responsable du projet attribue le rôle `admin` au compte de l’utilisateur désigné à sa création. [Accès admin](https://no-wave.fr/admin).

## Lancer le projet

Docker Compose requis. Depuis la racine :

```sh
test -f .env || cp .env.example .env
# Compléter .env et le chemin du compte de service Firebase avant de lancer.
docker compose up --build -d --wait
```

Site : [localhost:8443](https://localhost:8443), avec certificat local à accepter. Les migrations sont automatiques. `docker compose down` arrête la stack en gardant les données. Garder les secrets hors Git.

Pour les alertes et le nettoyage photo en local :

```sh
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

## Guides

- [Contrats API](docs/contrats-api.md) : routes, champs, réponses et erreurs.
- Développement : [backend](backend/README.md), [mobile](mobile/README.md), [web](web/README.md).
- [Tests](docs/tests.md) : commandes et recette sur appareil.
- [Déploiement](deploy/README.md) : livraison, configuration et sauvegardes.
- [Cartographie](docs/architecture/README.md) : sources, profondeurs et chargement.
- [Contribution](docs/contribuer.md) : branches et revue.

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).

NoWave ne remplace pas les informations nautiques officielles.
