# NoWave — POC MapLibre Android et iOS

Application Flutter autonome, sans clé API et sans intégration aux fonctions
métier/GPS. `maplibre_gl` reste fixé à 0.27.1 ; le même Dart, le même style v8
et les mêmes endpoints sont utilisés sur Android et iOS. Les données régionales
sont servies par NoWave, jamais incluses dans les assets, l’APK ou le bundle iOS.
Le cache local et les packs hors ligne restent une étape future, avec stockage
applicatif et APIs Flutter/Dart compatibles avec les deux plateformes.

## Serveur et URL commune

Après la génération réelle décrite dans
[FRANCE_MED_REAL.md](../cartography/FRANCE_MED_REAL.md) :

```bash
# Depuis la racine, dans un terminal séparé
python3 cartography/server.py --region france_med --host 0.0.0.0 --port 8765
```

L’URL se configure exclusivement par
`--dart-define=NOWAVE_STYLE_URL=...`. Le défaut `127.0.0.1` convient au développement
sur la même machine ; il n’est pas une adresse réseau de production.

| Client | URL de développement |
|---|---|
| Android USB avec `adb reverse` | `http://127.0.0.1:8765/style.json` |
| Émulateur Android | `http://10.0.2.2:8765/style.json` |
| Simulateur iOS sur le Mac du serveur | `http://127.0.0.1:8765/style.json` |
| Téléphone Android ou iPhone sur le LAN | `http://<IP_DU_SERVEUR>:8765/style.json` |
| Toutes plateformes en production | `https://<DOMAINE_NOWAVE>/style.json` |

Le téléphone doit pouvoir joindre l’adresse annoncée. Sous WSL, vérifier
l’exposition du port au LAN depuis Windows ; `adb reverse` n’est qu’une facilité
Android USB, pas une dépendance applicative.

## Android

Java/JDK 21 avec `javac` est requis par la dépendance native. Un JRE seul ne
suffit pas. Depuis la racine :

```bash
adb devices -l
adb -s "<ANDROID_DEVICE>" reverse tcp:8765 tcp:8765
cd map_poc
flutter pub get
flutter run -d "<ANDROID_DEVICE>" \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
```

L’accès Internet est déclaré dans le manifest principal. HTTP clair est désactivé
pour Release/Profile ; le manifest Debug le réactive explicitement pour le
serveur local. Le build ARM64 utilisé sous WSL est reproductible ainsi :

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH \
flutter build apk --debug --no-pub --target-platform android-arm64 \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH \
flutter build apk --release --no-pub --target-platform android-arm64 --split-per-abi \
  --dart-define=NOWAVE_STYLE_URL="https://<DOMAINE_NOWAVE>/style.json"
```

Pour un build Release, utiliser une URL HTTPS et la signature applicative prévue
pour la publication. Le POC utilise encore sa signature Debug pour ses builds
Release de contrôle ; il ne constitue pas un package signé pour un store.

## iOS : audit et validation sur Mac

Le projet cible iOS 15.0 et ARM64 ; le plugin accepte iOS 13.0 et utilise
MapLibre Native 6.28.0. Le projet contient l’intégration Swift Package Manager
`FlutterGeneratedPluginSwiftPackage` et le plugin fournit `Package.swift`.
L’absence de Podfile correspond à cette intégration ; ne pas ajouter une seconde
chaîne CocoaPods sans besoin identifié sur Mac.

`Runner/Info.plist` est utilisé par Release et Profile et ne désactive pas ATS.
Debug utilise `Runner/Info-Debug.plist`, avec `NSAllowsLocalNetworking` et exceptions CIDR pour loopback/réseaux privés IPv4 en Debug (iOS 17+) et le texte
de permission réseau local. Il n’y a pas de `NSAllowsArbitraryLoads` global.
Les deux plists doivent conserver les mêmes propriétés applicatives ; les tests
vérifient cette cohérence. Pour un domaine distant HTTP, utiliser HTTPS plutôt
qu’élargir les exceptions. L’accès LAN peut déclencher la permission réseau local
sur l’iPhone. Référence :
[Apple — NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

À exécuter sur macOS avec Xcode :

```bash
cd map_poc
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
flutter devices
flutter run -d "<IOS_SIMULATOR>" \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
# iPhone physique : serveur accessible sur le LAN
flutter run -d "<IPHONE_DEVICE>" \
  --dart-define=NOWAVE_STYLE_URL="http://<IP_DU_SERVEUR>:8765/style.json"
# Après configuration de la signature Apple, build de production
flutter build ios \
  --dart-define=NOWAVE_STYLE_URL="https://<DOMAINE_NOWAVE>/style.json"
```

**Build iOS non exécuté : nécessite macOS + Xcode.** L’audit statique depuis WSL
ne valide ni la résolution des paquets par Xcode ni le rendu natif sur iPhone.
Les API utilisées sont communes : création de carte, style JSON, caméra, gestes,
MVT, raster XYZ RGBA, GeoJSON, sprites et glyphes distants. Aucune API MapLibre
réservée à Android n’est appelée. La dépendance et son support iOS sont documentés
par [MapLibre 0.27.1](https://github.com/maplibre/flutter-maplibre-gl/releases/tag/v0.27.1).

## HTTPS et recette commune de rendu

En production, terminer TLS sur le reverse proxy du serveur et annoncer son URL
publique afin que tous les assets cartographiques utilisent le même domaine :

```bash
python3 cartography/server.py --region france_med --host 127.0.0.1 --port 8765 \
  --public-url "https://<DOMAINE_NOWAVE>"
```

`--public-url` configure les URLs du style ; il n’installe pas un certificat TLS.
Le relief Mapzen/AWS approuvé conserve son URL HTTPS externe et son attribution.
Glyphes Open Sans, sprites, GeoJSON, MVT et PNG sont servis par NoWave. Les PNG
absents renvoient HTTP 204 ; alpha=0 signifie profondeur inconnue et non 0 m.

Sur chaque appareil disponible, vérifier la façade à z7, puis Marseille, Sète,
Port-Vendres et Nice à z12–18 : pan/zoom, objets nautiques, toponymie, masque marin,
relief terrestre, courbes et trous NoData. Contrôler les requêtes serveur vers
les mêmes endpoints et l’absence de données DEMO dans `REGION_REAL`.
Aucun appareil Android ni environnement macOS n’était disponible lors du bilan
Linux du 4 octobre 2026 ; les contrôles physiques restent à effectuer.

Le serveur sans `--region` conserve la scène de démonstration. L’aperçu réel
Cassis sans bathymétrie utilise `--relief-preview --center 5.53 43.205 --zoom 12`.
Voir les scènes historiques dans [VISUAL_REVIEW.md](../cartography/VISUAL_REVIEW.md).
Le chargement Web reste `MapLibreJsSource.cdn()` ; la chaîne mobile est native.
