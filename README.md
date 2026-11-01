# NoWave

NoWave est une app de signalements maritimes : obstacles, animaux marins et pollution. Elle affiche les observations sur une carte et envoie des alertes à proximité.

[Télécharger l’app mobile](https://no-wave.fr/downloads/mobile/).

Le responsable du projet attribue le rôle `admin` au compte de l’utilisateur désigné à sa création, pour accéder à l’[administration](https://no-wave.fr/admin).

## Lancer le projet

Installer Docker avec Compose. Toutes les commandes ci-dessous partent de la racine du dépôt.

```sh
test -f .env || cp .env.example .env
```

Compléter `.env` avant de lancer : mot de passe PostgreSQL, clé web Firebase, `MAPBOX_PUBLIC_TOKEN` pour la carte web et accès au stockage photo Scaleway. `FIREBASE_SERVICE_ACCOUNT_FILE` doit pointer vers un vrai fichier de compte de service Firebase sur le poste. Remplacer les valeurs d’exemple et garder les secrets hors Git.

```sh
docker compose up --build -d --wait
```

Avec les ports par défaut, le site est sur `https://localhost:8443` : accepter le certificat local. L’admin est sous `/admin`, l’API sur `http://127.0.0.1:8000`. Les migrations sont automatiques ; les ports se règlent dans `.env`.

Pour les alertes et le nettoyage des photos :

```sh
docker compose --profile alerts --profile photos up -d notifications photo-cleanup
```

`docker compose down` arrête les services en conservant les données.

## Lancer le mobile depuis les sources

Installer Flutter 3.47.5 et configurer un émulateur ou un téléphone.

```sh
test -f mobile/.env.json || cp mobile/.env.example.json mobile/.env.json
```

Dans `mobile/.env.json`, renseigner `MAPBOX_ACCESS_TOKEN` avec un jeton public Mapbox et `API_BASE_URL` avec l’adresse du backend. Laisser `MARINE_API_BASE_URL` vide pour utiliser le même backend.

Pour l’API locale sur le port 8000 : `http://10.0.2.2:8000/` sur émulateur Android, `http://127.0.0.1:8000/` sur simulateur iOS. Sur téléphone, utiliser l’API distante ou, en USB Android, lancer `adb reverse tcp:8000 tcp:8000` et utiliser `http://127.0.0.1:8000/`.

```sh
(cd mobile && flutter pub get --enforce-lockfile)
(cd mobile && flutter run --dart-define-from-file=.env.json)
```

Après un changement de configuration, reconstruire et relancer l’app. Garder `mobile/.env.json` hors Git.

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

Les [crédits et licences](docs/licences.md) couvrent les données et les icônes. NoWave ne remplace pas les cartes nautiques officielles.

Documents de référence : [dossier Drive](https://drive.google.com/drive/folders/1tuDBQVBQNH7H6cWgftj46g7fPGZSxPQ2).
