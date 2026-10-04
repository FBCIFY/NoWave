# NoWave mobile

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

Compléter ensuite les deux adresses :

```json
{
  "NOWAVE_STYLE_URL": "https://adresse-du-serveur-cartographique/style.json",
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

Le style NoWave réel est chargé avec MapLibre, sans jeton cartographique.
`NOWAVE_STYLE_URL` peut aussi être passé directement avec `--dart-define`.
L’URL n’a pas de valeur locale implicite : configurez une adresse accessible à
l’appareil. HTTP local est autorisé en Debug ; Release requiert HTTPS.

Pour les données et le serveur, suivre [France Méditerranée](../cartography/FRANCE_MED_REAL.md).
Sur le poste possédant les données préparées, depuis la racine :

```bash
.venv/bin/python cartography/server.py --region france_med --host 0.0.0.0 --port 8765
```

Le serveur reprend le `Host` reçu dans les URLs des MVT, PNG, GeoJSON, glyphs et
sprites. Derrière un proxy HTTPS, utiliser `--public-url https://<DOMAINE>`.
Les données régionales restent sur le serveur, hors des bundles Flutter.
Les cartes affichent des profondeurs réelles SHOM uniquement dans leur couverture ;
le fond gris bleu ailleurs représente NoData.

Android sur le même LAN :

```bash
flutter run -d "<ANDROID_ID>" --dart-define-from-file=.env.json \
  --dart-define=NOWAVE_STYLE_URL="http://<IP_SERVEUR>:8765/style.json"
```

Le backend doit aussi être accessible : `.env.json` contient son `API_BASE_URL`
avec `/` final. Pour l’émulateur Android, utiliser `10.0.2.2` au lieu de l’IP LAN.
Pour le développement USB uniquement, `adb reverse tcp:8765 tcp:8765` permet
l’URL `http://127.0.0.1:8765/style.json`. Un backend USB local nécessite son
propre reverse pour le port 8000. Le fonctionnement LAN/HTTPS reste indépendant d’ADB.

Build ARM64 sur ce poste Linux (JDK 21 complet, avec `javac`) :

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH \
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define-from-file=.env.json
```

Le build Release utilise HTTPS pour le backend et la carte. Le signing Android
reste la clé Debug de développement existante ; ce build n’est pas une livraison Store.
Le parcours iPhone et simulateur est dans [IOS_TESTING.md](IOS_TESTING.md).

## Organisation du code

```text
lib/
├── main.dart          démarrage : Firebase, services partagés
├── app/               racine de l’app et thème
├── core/              outils partagés par toutes les fonctionnalités
│   ├── api/           client HTTP vers le backend
│   ├── haptics/       retours haptiques
│   ├── location/      position GPS et format degrés/minutes/secondes
│   ├── map/           adaptateur MapLibre, chargement du style
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
  --ios-bundle-id=fr.blueway-arcadia.app
```

Le projet de développement est `blueway-dev`. L’identifiant Android est
`fr.blueway.app` ; celui d’iOS est `fr.blueway-arcadia.app`. Les fichiers `.env`, les clés privées Firebase Admin et
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

- `maplibre_gl` 0.27.1 pour l’affichage et les interactions ;
- le style NoWave réel provenant du serveur configuré ;
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
L’application ne demande plus l’autorisation au lancement. Le token FCM est lu
au lancement suivant et seulement affiché dans les logs.

### Limites connues

- iOS n’affiche la demande système qu’une fois ; après un refus, seul le
  passage par les réglages fonctionne ;
- la ligne « Notifications » des réglages iOS n’apparaît qu’après une première
  demande ;
- les comptes créés avant NW-117 ne voient pas l’écran d’alertes ;
- `ProfileGate` n’a pas de test automatisé : le parcours a été vérifié à la
  main sur iPhone.

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

### Flèche de position

Un overlay Flutter bleu de 44 points suit la position GPS projetée et tourne
selon le cap du téléphone moins la rotation de la carte. Le modèle 3D historique
reste dans le dépôt, mais n’est plus embarqué. La boussole propose nord en haut,
cap du téléphone (actualisé en continu) ou rotation manuelle au doigt.
Un déplacement au doigt coupe le suivi ; le recentrage retrouve le zoom 14.
Pendant le placement d’un signalement, le GPS reste actif mais ne déplace pas
la caméra. Après fermeture, la caméra et le suivi antérieurs sont rétablis.

### Limites connues

- l’envoi de la photo suit le contrat de la doc technique mais n’a pas encore
  été testé sur le serveur : la route de NW-112 n’est pas définie dans le backend local actuel et
  répondra 404 ; utiliser un backend qui implémente ce contrat pour valider l’upload ;
- l’azimut dépend des perturbations magnétiques et de la calibration ;
- l’inclinaison n’a pas été vérifiée avec un support d’angle étalonné ;
- les conventions des capteurs doivent encore être validées sur Android réel ;
- la hauteur de caméra est fixée à 2,5 m pour le MVP.

## Référence isolée et validation de la migration

Le [POC MapLibre](../map_poc/README.md) reste une référence isolée du rendu.
L’application complète utilise maintenant le même moteur et le même serveur.
Voir [MAPLIBRE_VALIDATION.md](MAPLIBRE_VALIDATION.md) pour l’audit, les résultats
mesurés et les limites restantes des tests physiques et du backend.
