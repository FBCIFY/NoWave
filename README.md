# NoWave

NoWave permet de signaler un obstacle, un animal marin ou une pollution sur une carte, puis d’alerter les utilisateurs à proximité. L’app tourne sur Flutter, avec une API FastAPI et une base PostgreSQL/PostGIS.

[Télécharger l’app mobile](https://no-wave.fr/downloads/mobile/).

## Lancer en local

Avec Docker Compose installé, préparer le `.env` depuis la racine du dépôt :

```sh
test -f .env || cp .env.example .env
```

Renseigner les accès dans ce fichier :

- `NOWAVE_DB_PASSWORD` : mot de passe de la base.
- `FIREBASE_SERVICE_ACCOUNT_FILE` : chemin du fichier Firebase local.
- `FIREBASE_WEB_API_KEY` et `MAPBOX_PUBLIC_TOKEN` : connexion à l’admin et carte web.
- `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION`, `SCW_ACCESS_KEY`, `SCW_SECRET_KEY` : stockage photo.

Le fichier Firebase doit être présent sur le poste. Garder les secrets hors Git, puis démarrer la stack :

```sh
docker compose up --build -d --wait
```

- Site : `https://localhost:8443`.
- Admin : `https://localhost:8443/admin`.
- API : `http://127.0.0.1:8000`.

Accepter le certificat HTTPS local. La base est migrée au démarrage ; les ports se règlent dans `.env`.

À la création du compte désigné, le responsable du projet lui attribue le rôle `admin` pour accéder à l’[administration](https://no-wave.fr/admin).

Pour les alertes et le nettoyage des photos :

```sh
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

`docker compose down` arrête les services en conservant les données.

## Appeler l’API

Vérifier que le backend répond :

```sh
curl --fail http://127.0.0.1:8000/health
```

Pour les routes privées, placer l’ID token du compte connecté dans `FIREBASE_ID_TOKEN`. Ce token s’obtient après connexion Firebase ; la clé web Firebase ne sert pas à authentifier ces requêtes.

```sh
curl --fail -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  http://127.0.0.1:8000/api/v1/users/me
```

Sans profil NoWave, cette lecture renvoie 404. Le [contrat API](docs/contrats-api.md) décrit la création du profil, les payloads et les réponses de chaque route.

## Travailler sur le projet

- [Backend](backend/README.md), [mobile](mobile/README.md), [web](web/README.md) : lancer un composant et ses tests.
- [Déploiement](deploy/README.md) : configuration du VPS et livraison.
- [Architecture](docs/architecture.md) : rôle des services et organisation des données.
- [Couche marine](docs/couche-marine.md) : sources, niveaux de zoom et chargement de la carte.
- [Signalements et alertes](docs/signalements-et-alertes.md) : publication, photos et notifications.

Les [crédits et licences](docs/licences.md) couvrent les données et les icônes. NoWave ne remplace pas les cartes nautiques officielles.

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).
