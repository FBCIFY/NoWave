# NoWave mobile

Application Flutter pour consulter la carte, publier un signalement maritime et
recevoir des alertes à proximité. Firebase gère les comptes et les notifications ;
Mapbox affiche la carte.

## Lancer l’app

Utiliser la version de Flutter indiquée dans [les tests](../docs/TESTING.md).
Depuis `mobile/` :

```sh
cp .env.example.json .env.json
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env.json
```

Remplacer `<device-id>` par l’identifiant de l’émulateur ou du téléphone.
Les configurations Firebase Android et iOS sont déjà versionnées.

## Configurer le backend

Compléter le fichier local `.env.json` :

```json
{
  "MAPBOX_ACCESS_TOKEN": "jeton-public-mapbox",
  "API_BASE_URL": "https://api.no-wave.fr/",
  "MARINE_API_BASE_URL": ""
}
```

| Variable | Usage |
| --- | --- |
| `MAPBOX_ACCESS_TOKEN` | Jeton public Mapbox pour le fond de carte |
| `API_BASE_URL` | API principale : profil, signalements, photos, alertes et tuiles de signalements |
| `MARINE_API_BASE_URL` | Backend facultatif pour les données marines publiques ; vide, il reprend `API_BASE_URL` |

Les URL acceptent HTTP ou HTTPS, avec ou sans slash final. Un préfixe de proxy
est conservé. Une adresse invalide déclenche une erreur de configuration.
Le token Firebase est envoyé aux routes métier ; les couches marines publiques
et les URL signées des photos n’en reçoivent pas.

Pour une API locale, utiliser `http://10.0.2.2:8000/` sur l’émulateur Android,
`http://127.0.0.1:8000/` sur le simulateur iOS, ou l’adresse réseau du poste sur
un téléphone. Avec Android en USB, `adb reverse tcp:8000 tcp:8000` permet aussi
d’utiliser `http://127.0.0.1:8000/`.

Les anciennes variables `BATHYMETRY_TILES_URL` et `MAPTILER_STYLE_URL` ne sont
plus utilisées. Après un changement de configuration, reconstruire et relancer
complètement l’app. Garder `.env.json` et les clés privées hors de Git.

## Organisation du code

| Dossier | Contenu |
| --- | --- |
| `lib/main.dart` | Initialisation de Firebase, Mapbox et des services partagés |
| `lib/app/` | Racine de l’app et thème |
| `lib/core/` | Client API, GPS, appareils, capteurs et notifications |
| `lib/features/auth/` et `profile/` | Compte, profil, bateau et préférences |
| `lib/features/home/` et `alerts/` | Accueil, historique et ouverture des alertes |
| `lib/features/map/` | Carte, couches marines et interactions |
| `lib/features/reports/` et `camera/` | Publication, photo et estimation de position |

Dans chaque fonctionnalité, `data/` contient les appels externes, `domain/`
les modèles et règles, `presentation/` les écrans et widgets.

## Compte et préférences

Le parcours passe par la connexion Firebase, la vérification de l’e-mail, puis
la création du profil backend avec un pseudo unique. La lecture d’un profil
ne le crée pas. Après une réponse de création perdue, l’app relit le profil
si le serveur confirme qu’il existe déjà.

« Mot de passe oublié ? » déclenche un e-mail Firebase de réinitialisation.
Les mots de passe ne sont pas stockés dans PostgreSQL.

Le partage du pseudo, le partage du bateau et les alertes sont trois préférences
indépendantes, désactivées par défaut. La réception d’alertes demande aussi
l’autorisation système du téléphone. Après un refus, l’utilisateur peut ouvrir
les réglages depuis le profil.

## Carte et signalements

La carte utilise Mapbox Standard et la palette `MarinePalette`. Le GPS et le
recentrage restent indépendants des déplacements manuels de la carte.
`MapConfig.nativeArrowPuck` active la flèche 3D orange ; sa désactivation revient
au chevron et au pavillon du bateau.

Les signalements actifs viennent des tuiles authentifiées
`GET /api/v1/map/tiles/{z}/{x}/{y}.mvt` : carte de chaleur avant le zoom 9,
puis badges individuels. Un appui ouvre le détail relu auprès de l’API.
Le cache serveur dure 15 secondes ; l’affichage dépend aussi du rafraîchissement
Mapbox. Hors ligne, les badges déjà chargés peuvent rester visibles sans être
à jour. Un bandeau indique une couche indisponible et l’app réessaie.

Les seuils marins sont regroupés dans `lib/core/map/marine/marine_zoom.dart` :

| Couche | Préparation | Affichage |
| --- | --- | --- |
| Bathymétrie raster | — | Zoom 5 |
| Ports | Zoom 6 | Zoom 8, enrichissement au zoom 10 |
| Balisage | Zoom 10 | Fondu du zoom 10 au zoom 12 |
| Profondeurs | Zoom 12 | Zoom 13 |

Les objets publics sont chargés par famille via
`/api/v1/map/marine-features/{family}/{z}/{x}/{y}.geojson`.
Un appui long liste les objets proches, y compris ceux masqués par collision.
Voir [la conservation des couches](../docs/architecture/marine-zoom-persistence.md).
Ces données complètent la carte et ne remplacent pas une carte nautique officielle.

## Publier une observation

Le bouton `+` ouvre le formulaire : catégorie, commentaire facultatif de
250 caractères maximum et position choisie sur la carte. La publication envoie
`POST /api/v1/reports` avec un point GeoJSON `[longitude, latitude]` et un UUID
`client_report_id`, réutilisé lors d’un réessai pour éviter les doublons.

Avec une photo :

1. La caméra demande une précision GPS de 50 m ou mieux et une visée exploitable.
2. L’app fige la position, le cap et l’inclinaison au déclenchement.
3. `POST /api/v1/position-estimates` propose une position ; l’utilisateur la
   confirme ou la corrige sur la carte. Si le service est indisponible, il peut
   placer le point lui-même.
4. L’app redresse le JPEG, retire les EXIF et le réduit à 500 000 octets maximum.
5. Elle crée le signalement, puis envoie la photo en multipart dans le champ
   `file` de `POST /api/v1/reports/{id}/photo`.

Un échec d’upload laisse le signalement publié. Le formulaire propose de
réessayer la même photo ou de terminer sans elle. Il n’y a pas de brouillon
persistant ni de file d’envoi différé.

L’estimation utilise une hauteur de caméra de 2,5 m par défaut : elle reste
approximative et demande une confirmation sur la carte. Cap magnétique,
calibration et conventions des capteurs doivent être vérifiés sur appareil.
La caméra est libérée en arrière-plan et rouverte au retour.

Les photos publiées utilisent une URL signée valable cinq minutes. Après un
403, l’app relit une fois le détail pour obtenir une URL neuve.

## Alertes et suivi de l’appareil

Après création du profil, `PUT /api/v1/devices/current` enregistre l’identifiant
d’installation et le token FCM. Le token est `null` si les notifications ne
sont pas autorisées.

Le suivi envoie la dernière position GPS à
`PUT /api/v1/devices/current/position`, au plus une fois par minute : précision
maximale de 50 m et déplacement minimal de 50 m, sauf nette amélioration de
précision. Le serveur garde uniquement la dernière position. Le suivi peut
continuer en arrière-plan si les alertes sont activées ; une fermeture forcée
ou un arrêt par le système l’interrompt jusqu’à la réouverture.

L’historique vient de `GET /api/v1/users/me/alerts`. L’accueil recherche aussi
les alertes récentes au lancement, au retour au premier plan et toutes les
15 secondes tant que l’app est visible. Recevoir une alerte affiche un badge
et un sonar ; l’ouvrir cadre son signalement sur la carte principale. Le détail
est relu auprès de l’API. Un parcours de publication en cours retarde cette
navigation sans effacer le formulaire.

À la déconnexion, l’app arrête les envois, désactive l’appareil côté backend,
puis ferme la session Firebase. Si le nettoyage serveur échoue, elle conserve
la session et propose de réessayer : le changement de compte attend donc le réseau.

## Vérifier et compiler

Depuis `mobile/` :

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --coverage
flutter build apk --debug --dart-define-from-file=.env.json
```

Les tests utilisent des doubles pour les services externes. Tester séparément
sur Android et iOS la caméra, le GPS, les autorisations, FCM et le retour depuis
l’arrière-plan. Les notifications distantes ne se valident pas avec le seul
simulateur iOS. Une livraison Android ou iOS demande aussi la configuration de signature de la
plateforme ; le build debug ci-dessus sert aux essais locaux.
