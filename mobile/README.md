# BlueWay mobile

## Développement

Depuis le dossier `mobile/` :

```bash
flutter pub get
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env.json
```

Remplacer `<device-id>` par l’identifiant affiché par `flutter devices`.

## Configuration locale

Créer le fichier local depuis l’exemple :

```bash
cp .env.example.json .env.json
```

Compléter ensuite les trois valeurs :

```json
{
  "MAPBOX_ACCESS_TOKEN": "jeton-public-mapbox",
  "MAPTILER_STYLE_URL": "https://api.maptiler.com/maps/ocean-v4/style.json?key=cle-maptiler",
  "API_BASE_URL": "https://adresse-du-backend/"
}
```

`API_BASE_URL` doit se terminer par `/`. Pour un backend lancé sur le poste de
développement, utiliser :

- Android Emulator : `http://10.0.2.2:8000/`
- simulateur iOS : `http://127.0.0.1:8000/`
- téléphone physique : `http://<adresse-ip-du-poste>:8000/`

Le téléphone physique et le poste doivent être sur le même réseau. Une
modification de `.env.json` nécessite un redémarrage complet de `flutter run`.
Le fichier `.env.json` ne doit jamais être ajouté à Git.

`MAPTILER_STYLE_URL` n’est plus lu par l’application : la carte utilise le
style Mapbox Standard.

## Organisation du code

```text
lib/
├── main.dart          démarrage : Firebase, Mapbox, services partagés
├── app/               racine de l’app et thème
├── core/              outils partagés par toutes les fonctionnalités
│   ├── api/           client HTTP vers le backend
│   ├── haptics/       retours haptiques
│   ├── location/      position GPS et format degrés/minutes/secondes
│   ├── map/           réglages Mapbox communs
│   ├── notifications/ autorisation du téléphone et messages push
│   └── sensors/       cap et inclinaison du téléphone
└── features/          une fonctionnalité par dossier
    ├── auth/          connexion, inscription, vérification de l’e-mail
    ├── profile/       création du profil, préférences, écran d’alertes
    ├── home/          accueil (la carte + accès au profil)
    ├── map/           carte, boussole, mode signalement
    ├── reports/       formulaire et envoi des signalements
    └── camera/        prise de photo, mesures et estimation de position
```

Chaque dossier de `features/` suit le même découpage :

- `data/` : appels au backend ou à Firebase ;
- `domain/` : modèles et règles sans interface ;
- `presentation/` : écrans et widgets.

Les services sont créés une seule fois dans `main.dart`, puis transmis aux
écrans. Les services qui appellent le backend reçoivent `getIdToken` pour
ajouter le token Firebase.

Enchaînement des écrans :

```text
AuthGate          (session Firebase)
├── LoginScreen / RegisterScreen
├── VerifyEmailScreen
└── ProfileGate   (profil du backend)
    ├── ProfileSetupScreen
    ├── AlertsOnboardingScreen   une seule fois, après la création du profil
    └── HomeScreen → MapScreen
                     ├── ProfileScreen (bouton profil)
                     ├── ReportComposerSheet (bouton +, signalement manuel)
                     └── CameraScreen (bouton appareil photo)
                         └── ReportComposerSheet → ReportPhotoViewer
```

`AuthGate` et `ProfileGate` choisissent l’écran à afficher. Les écrans eux-mêmes
ne naviguent presque pas : ils déclenchent une action et l’aiguillage suit.

Fichiers présents mais non utilisés par l’application :

- `features/demo/` : compteur du modèle Flutter ;
- `features/reports/presentation/reports_screen.dart` et
  `data/demo_reports_service.dart` : liste de démonstration, utilisée
  seulement dans les tests ;
- `app/router.dart` : fichier vide.

## Authentification et profil — NW-51

L’application utilise Firebase Authentication avec le fournisseur
e-mail/mot de passe.

Le parcours comprend :

- la création du compte ;
- l’envoi et la vérification automatique de l’adresse e-mail ;
- la connexion et la déconnexion ;
- la transmission du token Firebase au backend ;
- la création d’un profil avec un nom d’utilisateur unique ;
- la récupération du profil existant sans création implicite.

Les fichiers Firebase Android et iOS sont versionnés. Après un clone,
`flutter pub get` suffit pour utiliser la configuration existante.

Firebase CLI et FlutterFire CLI servent uniquement à modifier ou régénérer
cette configuration.

Sur macOS :

```bash
brew install firebase-cli
dart pub global activate flutterfire_cli
gem install xcodeproj
```

Sur Windows :

```powershell
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

Pour régénérer la configuration :

```bash
firebase login
flutterfire configure \
  --project=blueway-dev \
  --platforms=android,ios \
  --android-package-name=fr.blueway.app \
  --ios-bundle-id=fr.blueway.app
```

Le projet de développement est `blueway-dev` et l’identifiant des applications
est `fr.blueway.app`. Les fichiers `.env`, les clés privées Firebase Admin et
les mots de passe ne doivent jamais être ajoutés à Git.

La connexion Google, la connexion Apple et la récupération du mot de passe ne
font pas partie de NW-51.

## Récupération du mot de passe — NW-52

Depuis la connexion, « Mot de passe oublié ? » permet de demander un lien de
réinitialisation. L’adresse déjà saisie est préremplie. Firebase envoie le
courriel et héberge la page où l’utilisateur choisit son nouveau mot de passe.
L’application affiche les erreurs de saisie et de réseau, puis permet de
revenir à la connexion.

Aucun mot de passe n’est enregistré dans PostgreSQL. Si le courriel n’arrive
pas, vérifier aussi les courriers indésirables.

## Vérifications

```bash
dart format lib test
flutter analyze
flutter test
```

## Carte maritime et localisation

La carte utilise :

- le SDK Mapbox pour l’affichage et les interactions ;
- le style Mapbox Standard pour le fond ;
- Geolocator pour récupérer la position de l’appareil.

L’écran permet de demander la permission de localisation, d’afficher la
position en degrés, minutes et secondes (par exemple `48° 23′ 12″ N`), et de
recentrer la carte. Déplacer la carte ne
modifie pas la dernière position GPS affichée.

## Signalement manuel — NW-54

Depuis la carte, le bouton `+` ouvre un formulaire avec trois catégories et un
commentaire facultatif de 250 caractères maximum. Déplacer la carte sous le
repère choisit la position. La publication envoie le token Firebase à
`POST /api/v1/reports` avec un point GeoJSON `[longitude, latitude]`, la date
du signalement et un `client_report_id` UUID. Un nouvel essai sans modification
réutilise le même identifiant pour éviter les doublons.

L’API locale doit inclure l’endpoint backend de NW-104 pour tester la
publication sur téléphone ; une ancienne version du backend répondra 404.

## Consentements et alertes — NW-117

L’écran profil propose trois préférences indépendantes, désactivées par
défaut :

- afficher le nom d’utilisateur ;
- afficher les informations du bateau ;
- recevoir les alertes.

Chaque changement envoie `PATCH /api/v1/users/me` avec seulement le champ
modifié. L’interrupteur change tout de suite ; en cas d’erreur, il revient à
sa valeur précédente et un message s’affiche.

La préférence « alertes » est distincte de l’autorisation de notifications du
téléphone. L’écran profil affiche l’état de cette autorisation et le relit au
retour dans l’application. En activant les alertes :

- si le téléphone n’a encore jamais demandé, la demande système s’affiche ;
- si l’autorisation a été refusée, les réglages du téléphone s’ouvrent ;
- si elle est déjà accordée, rien de plus.

Juste après la création du profil, un écran explique les alertes avec deux
choix : « Activer les alertes » (préférence + demande système) ou « Plus tard ».
L’application ne demande plus l’autorisation au lancement. Le token FCM est
envoyé au backend avec l’enregistrement du téléphone (voir NW-116).

### Limites connues

- iOS n’affiche la demande système qu’une fois ; après un refus, seul le
  passage par les réglages fonctionne ;
- la ligne « Notifications » des réglages iOS n’apparaît qu’après une première
  demande ;
- les comptes créés avant NW-117 ne voient pas l’écran d’alertes ;
- `ProfileGate` n’a pas de test automatisé : le parcours a été vérifié à la
  main sur iPhone.

## Couche des signalements — NW-114

Les signalements actifs sont affichés par-dessus le fond Mapbox, dans une
couche à part (`ReportTiles`). Les tuiles MVT viennent du backend,
`GET /api/v1/map/tiles/{z}/{x}/{y}.mvt`, avec le token Firebase.

- **De loin (zoom < 9)** : le backend regroupe les signalements proches. La
  carte montre une zone colorée qui bat doucement, du jaune au rouge selon le
  nombre de signalements, avec ce nombre écrit dessus. Toucher le nombre
  rapproche la carte de deux niveaux. Le battement s'arrête en arrière-plan et
  quand l'option « Réduire les animations » du téléphone est active.
- **De près (zoom ≥ 9)** : un badge par signalement, à l'icône et à la couleur
  de sa catégorie. Les badges ne se masquent jamais entre eux. Entre 8,5 et
  9,5, la zone s'efface pendant que les badges apparaissent.

Toucher un badge ouvre la fiche du signalement (`ReportDetailSheet`),
chargée par `GET /api/v1/reports/{id}` : catégorie, date d'observation,
position en degrés/minutes/secondes, distance et direction depuis
l'utilisateur en milles nautiques, auteur et bateau s'ils sont rendus
publics, état de la photo et fin du signalement. Un signalement expiré ou
retiré entre-temps affiche « n'est plus disponible » ; les autres erreurs
proposent de réessayer.

### Rafraîchissement

Le backend sert les tuiles avec `Cache-Control: max-age=15`. Mapbox redemande
lui-même les tuiles visibles une fois expirées et les remplace sans effacer
les badges : un signalement publié, retiré ou expiré apparaît ou disparaît en
15 s environ, sans code côté application. Comme les tuiles sont redemandées
en continu, l'application redonne le token Firebase à Mapbox toutes les
4 minutes et au retour au premier plan, pour qu'il n'expire jamais.

Si une tuile échoue (réseau, token), la carte reste utilisable et affiche
« Signalements momentanément indisponibles. » La carte ne fonctionne pas hors
ligne : les badges déjà affichés peuvent rester visibles sans être à jour.

### Limite de débit du serveur

nginx limite chaque appareil à 10 requêtes/s (pointes à 30) et à 30
connexions. Pour rester en dessous, la source demande le moins de tuiles
possible : aucune au-delà du zoom 12 (Mapbox agrandit celles du zoom 12, qui
placent déjà un badge à 2 m près), pas de préchargement des zooms inférieurs,
et rien pendant un geste. Une tuile refusée (429, ou 503 quand il y a trop de
connexions) n'affiche pas le bandeau : Mapbox la redemande lui-même quelques
secondes plus tard.

### Position de l'utilisateur

De près, la flèche 3D (voir plus bas) ; de loin, un point bleu, plus lisible.
Un halo bleu sous les signalements montre la précision du GPS.

### Limites connues

- vérifié à la main sur iPhone uniquement, pas encore sur Android ;
- le rafraîchissement dépend de l'en-tête `Cache-Control` du backend : si
  `max-age` change, la fréquence de mise à jour de la carte change aussi ;
- hors ligne, les badges déjà affichés restent visibles sans être à jour ;
  seul le message « momentanément indisponibles » le signale ;
- l'état de la photo reste « Envoi en cours » tant que la route d'envoi de
  NW-112 n'est pas déployée ;
- en zoomant ou dézoomant vite, nginx refuse encore des tuiles (429) : les
  badges arrivent quelques secondes après la fin du geste, en attendant une
  limite propre aux tuiles côté serveur ;
- les regroupements sont calculés tuile par tuile, aux zooms entiers : en
  dézoomant, ils fusionnent par sauts, et deux zones proches séparées par une
  limite de tuile ne fusionnent qu'à un zoom plus bas.

## Signalement photo — NW-55, NW-115

Le bouton appareil photo de la carte ouvre `CameraScreen` en plein écran.
Le parcours reprend le prototype caméra de NW-55 :

1. La caméra arrière affiche l’aperçu, la position GPS et sa précision. La
   capture est bloquée tant que la précision dépasse 50 mètres.
2. Au déclenchement, l’azimut, l’inclinaison (lue sur l’accéléromètre),
   l’altitude et la position sont figés avec la photo.
3. « Continuer » envoie ces mesures à `POST /api/v1/position-estimates`, avec
   une hauteur de caméra de 2,5 m (source `default`). Rien n’est enregistré
   côté serveur.
4. De retour sur la carte, le repère est placé sur la position estimée.
   L’utilisateur la confirme ou la corrige en déplaçant la carte. Sans
   estimation, il place lui-même le point sur l’objet photographié.
5. La photo est redressée, débarrassée de ses EXIF et réduite à 500 000 octets
   au plus (`report_jpeg.dart`).
6. « Publier » crée le signalement (`POST /api/v1/reports`), puis envoie la
   photo à part : `POST /api/v1/reports/{id}/photo`, en multipart, champ
   `file`. L’envoi est réussi si la réponse contient
   `"upload_status": "uploaded"`.

Si l’envoi de la photo échoue, le signalement reste publié. « Réessayer
l’envoi » renvoie la même photo pour le même signalement ; « Terminer sans
photo » ferme le formulaire. Le formulaire et la photo restent en mémoire
tant que le parcours est ouvert, mais rien n’est gardé après fermeture : pas
de brouillon, pas de file d’attente, pas d’envoi automatique plus tard.

La vignette ouvre la photo en plein écran (`ReportPhotoViewer`). Fermer un
signalement rempli demande une confirmation.

### Azimut de la caméra — NW-150

L’azimut envoyé est celui de l’axe de visée de la caméra arrière, par rapport
au nord vrai :

- sur Android, `precise_compass` donne le cap du haut du téléphone, faux quand
  on le tient debout pour photographier. `MainActivity` envoie donc la matrice
  de rotation du téléphone (canal `fr.blueway.app/rotation_matrix`) ;
  `camera_azimuth.dart` en tire l’axe de la caméra, le projette à
  l’horizontale et calcule son azimut. La déclinaison magnétique vient de
  `precise_compass` (cap vrai − cap magnétique) ;
- sur iOS, le cap vrai de CoreLocation suit déjà la caméra (à vérifier dans
  NW-128) ;
- caméra presque verticale (sol ou ciel), l’azimut n’a pas de sens : la photo
  est bloquée avec « Relevez le téléphone vers l’horizon. ».

### Flèche de position

La position de l’utilisateur est affichée par une flèche 3D qui suit le cap
du téléphone. Le modèle `assets/models/location_puck.glb` est généré par un
script ; pour le modifier, changer le script puis, depuis `mobile/` :

```bash
python3 tool/make_location_puck.py assets/models/location_puck.glb
```

### Limites connues

- l’envoi de la photo suit le contrat de la doc technique mais n’a pas encore
  été testé sur le serveur : la route de NW-112 n’est pas déployée et répond
  404 (« envoi indisponible sur ce serveur ») ;
- l’azimut dépend des perturbations magnétiques et de la calibration ;
- l’inclinaison n’a pas été vérifiée avec un support d’angle étalonné ;
- les conventions des capteurs doivent encore être validées sur Android réel,
  avec une cible connue ;
- la hauteur de caméra est fixée à 2,5 m pour le MVP.

## Appareil et position — NW-116

Une fois le profil créé, le téléphone s'enregistre auprès du backend pour
recevoir les alertes à proximité (`DeviceRegistration`) :

- `PUT /api/v1/devices/current` envoie l'identifiant d'installation, la
  plateforme et le token FCM. L'envoi a lieu à l'ouverture, à chaque retour
  dans l'application et à chaque nouveau token ;
- si les notifications ne sont pas autorisées, le token envoyé est `null`. Le
  backend efface alors l'ancien token, et le téléphone reste enregistré pour
  sa position ;
- si le backend répond 409 (token ou identifiant déjà pris par un autre
  appareil), l'application demande un nouveau token, puis, si ça ne suffit
  pas, un nouvel identifiant.

L'identifiant d'installation est un UUID gardé sur le téléphone avec
`shared_preferences` (`InstallationIdStore`). Le backend le lie au premier
compte qui l'enregistre.

### Position GPS

Tant que l'application est visible, `DevicePositionReporter` envoie la
dernière mesure GPS à `PUT /api/v1/devices/current/position`, avec l'en-tête
`X-Installation-ID`, au plus une fois toutes les 60 s. La première mesure part
dès qu'elle arrive. Le serveur ne garde que la dernière position, sans
historique.

- une mesure dont la précision dépasse 50 m n'est pas envoyée ;
- en dessous de 1 m/s (environ 2 nœuds), le cap est envoyé à `null` ;
- la position vient du GPS : déplacer la carte ne la change pas ;
- l'application ne demande pas la localisation pour ce suivi : sans
  autorisation, rien n'est envoyé ;
- en arrière-plan, le suivi s'arrête ; il reprend au retour ;
- sans réseau, la mesure est gardée pour l'envoi suivant ;
- un 404 (appareil inactif) relance l'enregistrement, puis l'envoi ;
- un 409 (mesure plus ancienne que celle du serveur) abandonne la mesure.

### Déconnexion

Avant `signOut`, l'application :

1. bloque les reprises GPS/FCM et attend la fin des envois en cours ;
2. désactive le téléphone (`DELETE /api/v1/devices/current`, avec l'en-tête
   `X-Installation-ID`) ;
3. tente de supprimer le token FCM, même si le serveur n'a pas répondu ;
4. oublie l'identifiant d'installation seulement après confirmation du
   nettoyage serveur, puis ferme la session Firebase. Le compte suivant
   reçoit un nouvel identifiant.

Si le `DELETE` échoue, une fenêtre explique que la déconnexion reste à terminer
et propose de réessayer ou d'annuler. L'identifiant et la session de l'ancien
compte sont conservés : la nouvelle tentative utilise toujours ses droits. Un
retour au premier plan ne relance pas les envois GPS/FCM pendant cette
transition. « Annuler » garde l'utilisateur sur son compte et relance
l'enregistrement du téléphone et le suivi GPS.

Seuls un succès du `DELETE` ou un 404 métier `device_not_found` / `user_not_found`
confirment qu'il ne reste rien à nettoyer pour ce compte. Un 404 de proxy ou une
erreur d'authentification ne permettent pas de poursuivre. Si le serveur a
confirmé le nettoyage, une erreur d'invalidation FCM est journalisée mais ne
bloque pas la fermeture de session : l'ancien appareil n'a plus de token côté
backend. Si seule la fermeture Firebase échoue, le prochain essai ne recrée
pas d'appareil et ne répète pas un nettoyage déjà terminé.

Après fermeture forcée de l'application pendant un échec serveur, la session
Firebase et l'ancien identifiant restent conservés. L'utilisateur peut reprendre
la déconnexion depuis ce même compte. Les tests automatisés couvrent la
conservation de l'identifiant et les requêtes authentifiées ; les essais sur
deux comptes réels et après relancement sont à consigner dans NW-128.

### Limites connues

- hors ligne, la déconnexion et le changement de compte attendent le retour
  du réseau. Tant que le nettoyage n'est pas confirmé, l'appareil peut rester
  actif côté backend, mais le mobile conserve sa référence et la session ;
- un enregistrement raté n'est pas réessayé tout de suite : il est refait au
  prochain retour dans l'application, ou au prochain envoi de position (404) ;
- sur le simulateur iOS, il n'y a pas de token APNs : le téléphone est
  enregistré avec un token `null` ;
- aucune position n'est envoyée en arrière-plan ;
- tests sur iPhone et Android en cours.
