# Tester NoWave mobile sur le Mac de Vadim

Cette branche lance **mobile/**, avec Firebase, profils, GPS, caméra et
signalements. Le style MapLibre 0.27.1 est le même sur Android et iOS.

**BUILD IOS NON EXÉCUTÉ — RAISON : macOS + Xcode requis.**
L’audit de configuration sous Linux ne remplace pas un build ni un test iPhone.

## Récupérer et préparer

Prérequis : Flutter 3.47.6 / Dart 3.13.5 (versions de validation), Xcode et
ses outils, iOS 15 minimum. Depuis le clone NoWave :

```bash
git fetch origin
git switch feat/NW-map-style
git pull --ff-only
cd mobile
flutter clean
flutter pub get
cd ios
# Ce dépôt utilise déjà Swift Package Manager et n’a pas de Podfile.
# Seulement si Flutter génère un Podfile pour un futur plugin sans SwiftPM :
if [ -f Podfile ]; then pod install; fi
cd ..
flutter doctor
flutter analyze
flutter test
flutter devices
```

Les dix plugins iOS résolus possèdent un `Package.swift`. Le projet référence
`FlutterGeneratedPluginSwiftPackage`, et le scheme prépare les frameworks Flutter.
Aucune migration vers CocoaPods n’est nécessaire. Xcode résout MapLibre Native
6.28.0 à partir du package du plugin. Les anciens pins propriétaires ont été
retirés. Ne pas lancer `pod repo update` dans ce projet sans Podfile.
Voir le [fonctionnement SwiftPM de Flutter](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

Créer la configuration locale (non versionnée) :

```bash
cp .env.example.json .env.json
```

Remplacer les deux adresses par des serveurs réellement accessibles.
`API_BASE_URL` se termine par `/` ; l’authentification et le profil utilisent
le backend Firebase actuel, et les estimations utilisent `/api/v1/position-estimates`.
Les fichiers Firebase existants sont conservés ; aucune clé cartographique n’est requise.

## Serveur de cartes

Le serveur doit déjà posséder les [données préparées](../cartography/FRANCE_MED_REAL.md).
Elles ne sont pas embarquées dans l’application ni dans cette branche Git.
Sur le poste/serveur qui les possède, depuis la racine du dépôt :

```bash
.venv/bin/python cartography/server.py --region france_med --host 0.0.0.0 --port 8765
```

Autoriser TCP 8765 sur ce poste. Si le serveur est dans WSL en mode NAT,
configurer le routage/forwarding Windows vers WSL, ou utiliser un serveur
accessible directement ; l’IP interne WSL n’est pas automatiquement une IP LAN. Le style reprend le Host du client pour ses
sources, sprites et glyphs. Derrière un proxy HTTPS, passer
`--public-url https://<DOMAINE>` au serveur. Le relief terrestre externe existant
reste sur son URL HTTPS. Si les données sont sur le PC Linux, le Mac et l’iPhone
utilisent l’IP de ce PC ; il n’est pas nécessaire de les copier sur le Mac.

## Lancer l’application complète

Les commandes incluent `.env.json` pour configurer aussi le backend.

Simulateur, **seulement si le serveur de cartes tourne sur ce même Mac** :

```bash
flutter run -d "<SIMULATOR_ID>" --dart-define-from-file=.env.json \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

Si le serveur tourne ailleurs, utiliser son IP LAN à la place du loopback.
La boussole réelle est indisponible dans le simulateur ; la caméra, la précision
GPS et les capteurs doivent être testés sur iPhone.

Sur iPhone et serveur dans le même réseau :

```bash
flutter run -d "<IPHONE_ID>" --dart-define-from-file=.env.json \
  --dart-define=NOWAVE_STYLE_URL="http://<IP_SERVEUR>:8765/style.json"
```

Sur iPhone avec serveur HTTPS :

```bash
flutter run -d "<IPHONE_ID>" --dart-define-from-file=.env.json \
  --dart-define=NOWAVE_STYLE_URL="https://<DOMAINE>/style.json"
```

Sur iPhone, `127.0.0.1` est l’iPhone lui-même. Le backend configuré dans `.env.json`
doit lui aussi être accessible depuis cet appareil ; le serveur cartographique
sur 8765 et le backend sur 8000 sont deux services distincts.

## Permissions, transport et signature

Debug utilise `Runner/Info-Debug.plist` : description d’accès au réseau local,
`NSAllowsLocalNetworking`, exceptions HTTP limitées à loopback et aux réseaux
privés IPv4 (127/8, 10/8, 172.16/12, 192.168/16). Les exceptions par IP/CIDR
couvrent aussi la politique ATS iOS 17+ ; aucun `NSAllowsArbitraryLoads` global.
Pour un serveur HTTP local en IPv6, utiliser un nom `.local` ou HTTPS.
Release et Profile utilisent `Runner/Info.plist`, sans exception ATS : HTTPS.
[Référence ATS Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Autoriser le réseau local au premier accès (Réglages → NoWave en cas de refus),
la localisation pendant l’utilisation et la caméra. La description de mouvement
explique l’inclinaison photo. Aucun micro ni accès à la photothèque n’est utilisé.
Les notifications passent par la demande existante dans le profil ; l’entitlement
APNs et les modes `fetch` / `remote-notification` sont conservés.

Le Team existant est `JTTQ2PFTCJ`, le Bundle Identifier iOS est
`fr.blueway-arcadia.app` (distinct de l’Android `fr.blueway.app` et cohérent avec
la configuration Firebase iOS existante). Si Vadim n’a pas accès à cette équipe :

```bash
open ios/Runner.xcworkspace
```

Choisir une Team autorisée dans Runner → Signing & Capabilities.
Un changement de Bundle Identifier nécessite aussi une application Firebase iOS
correspondante et sa configuration ; ne pas le changer simplement pour ignorer
une erreur de signature. APNs sur appareil exige le provisioning correspondant.

Build sur le Mac :

```bash
flutter build ios --simulator --dart-define-from-file=.env.json
# Avec le provisioning disponible et les deux serveurs configurés en HTTPS :
flutter build ios --dart-define-from-file=.env.json
```

## Parcours à vérifier sur appareil

Connexion, profil, affichage des MVT/PNG alpha/GeoJSON/sprites/glyphs, position et
flèche, recentrage, suivi, geste qui coupe le suivi, nord/cap/rotation manuelle ;
puis signalement manuel, caméra plein écran, JPEG, estimation, correction du point,
confirmation d’abandon, publication et réessai photo. Vérifier le chargement d’erreur
et son bouton Réessayer, ainsi que le retour dans l’app après permission refusée.

**Limite backend actuelle :** la branche conserve le contrat client d’upload
`POST /api/v1/reports/{id}/photo`, mais le backend local de dev ne définit pas
cette route. Le serveur utilisé doit l’implémenter pour tester un envoi réel.
Les tests du client utilisent un backend simulé ; ils ne valident pas un upload
sur le serveur. Le fond régional reste une carte de test, sans certification nautique.
