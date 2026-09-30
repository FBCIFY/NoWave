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
    └── camera/        prototype caméra et capteurs (BLU-55)
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
                     └── ProfileScreen (bouton profil)
```

`AuthGate` et `ProfileGate` choisissent l’écran à afficher. Les écrans eux-mêmes
ne naviguent presque pas : ils déclenchent une action et l’aiguillage suit.

Fichiers présents mais non utilisés par l’application :

- `features/demo/` : compteur du modèle Flutter ;
- `features/reports/presentation/reports_screen.dart` et
  `data/demo_reports_service.dart` : liste de démonstration, utilisée
  seulement dans les tests ;
- `features/camera/` : prototype BLU-55, aucun bouton n’y mène ;
- `app/router.dart` : fichier vide.

## Authentification et profil — BLU-51

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
font pas partie de BLU-51.

## Récupération du mot de passe — BLU-52

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

## Signalement manuel — BLU-54

Depuis la carte, le bouton `+` ouvre un formulaire avec trois catégories et un
commentaire facultatif de 250 caractères maximum. Déplacer la carte sous le
repère choisit la position. La publication envoie le token Firebase à
`POST /api/v1/reports` avec un point GeoJSON `[longitude, latitude]`, la date
du signalement et un `client_report_id` UUID. Un nouvel essai sans modification
réutilise le même identifiant pour éviter les doublons.

L’API locale doit inclure l’endpoint backend de BLU-104 pour tester la
publication sur téléphone ; une ancienne version du backend répondra 404.

## Consentements et alertes — BLU-117

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
- les comptes créés avant BLU-117 ne voient pas l’écran d’alertes ;
- `ProfileGate` n’a pas de test automatisé : le parcours a été vérifié à la
  main sur iPhone.

## Prototype caméra et capteurs — BLU-55

Le prototype permet de :

- afficher et capturer l’aperçu de la caméra arrière ;
- afficher la position GPS et sa précision ;
- bloquer la capture lorsque la précision dépasse 50 mètres ;
- mesurer l’azimut, l’inclinaison et l’altitude ;
- figer les mesures associées au moment de la capture.

### Limites connues

- l’azimut dépend des perturbations magnétiques et de la calibration ;
- l’inclinaison n’a pas été vérifiée avec un support d’angle étalonné ;
- les conventions des capteurs doivent encore être validées sur Android réel ;
- la précision verticale ne suffit pas seule à calculer une position ;
- la photo reste dans le stockage temporaire de l’application.
