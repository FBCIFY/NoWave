# NoWave

NoWave est une app de signalements maritimes : obstacles, animaux marins et pollution. Elle affiche les observations sur une carte et envoie des alertes à proximité.

[Télécharger l’app mobile](https://no-wave.fr/downloads/mobile/).

Le responsable du projet attribue le rôle `admin` au compte de l’utilisateur désigné à sa création, pour accéder à l’[administration](https://no-wave.fr/admin).

## Prérequis

- Docker avec Compose.
- Un compte de service Firebase et les clés renseignées dans `.env`.

## Lancer

Depuis la racine du dépôt :

```sh
test -f .env || cp .env.example .env
```

Dans `.env`, remplacer les valeurs d’exemple :

- `NOWAVE_DB_PASSWORD` : mot de passe de la base.
- `FIREBASE_SERVICE_ACCOUNT_FILE` : chemin du fichier Firebase local.
- `FIREBASE_WEB_API_KEY` et `MAPBOX_PUBLIC_TOKEN` : connexion admin et carte web.
- `PHOTO_STORAGE_BUCKET`, `PHOTO_STORAGE_REGION`, `SCW_ACCESS_KEY`, `SCW_SECRET_KEY` : stockage photo.

Garder ce fichier et les clés privées hors Git.

```sh
docker compose up --build -d --wait
```

Adresses par défaut :

- Site : `https://localhost:8443`.
- Admin : `https://localhost:8443/admin`.
- API : `http://127.0.0.1:8000`.

Accepter le certificat HTTPS local. Les migrations sont automatiques ; les ports se règlent dans `.env`.

Pour les alertes et le nettoyage des photos :

```sh
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

`docker compose down` arrête les services en conservant les données.

## Utiliser l’API

Vérifier que le backend répond :

```sh
curl --fail http://127.0.0.1:8000/health
```

Pour les routes privées, `FIREBASE_ID_TOKEN` doit contenir l’ID token du compte connecté, obtenu après connexion Firebase. Il s’agit du token utilisateur, pas de la clé web Firebase.

```sh
curl --fail -H "Authorization: Bearer $FIREBASE_ID_TOKEN" \
  http://127.0.0.1:8000/api/v1/users/me
```

Cette lecture renvoie 404 si le profil n’a pas encore été créé. Les routes, champs, réponses et erreurs sont dans les [contrats API](docs/contrats-api.md).

## Par composant

Chaque README donne le lancement et les tests courants :

- [Backend](backend/README.md) : API Python et base locale.
- [Mobile](mobile/README.md) : app Flutter sur émulateur ou téléphone.
- [Web](web/README.md) : site en développement avec Vite.
- [Déploiement](deploy/README.md) : configuration du VPS et vérifications après livraison.

Les [crédits et licences](docs/licences.md) couvrent les données et les icônes. NoWave ne remplace pas les cartes nautiques officielles.

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).
