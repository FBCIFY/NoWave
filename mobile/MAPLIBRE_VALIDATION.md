# Audit et migration de l’application NoWave complète

Validation du 4 octobre 2026, Linux/WSL. Les résultats automatisés et les builds
ci-dessous ne sont pas une validation sur téléphone.

## A. Git avant intervention

Branche : `feat/NW-map-style`, HEAD `dd2bb77cc2f3333c4ba3d52f3fddd9806441e44f`.
Arbre propre, trois commits locaux devant `origin/feat/NW-map-style` (`20d86ab`).
Après fetch, `origin/dev` = `bcef3865323de5760524d8a937e3459e0349b233`,
ancêtre de HEAD ; comparaison `origin/dev...HEAD` : 0 commits côté dev, 20 ici.
Aucun merge/rebase nécessaire, aucun changement sur dev.

Les trois commits locaux préservés :

- `76ad67e` acquisition et préparation des sources réelles ;
- `78d4562` configuration réseau Android/iOS du POC ;
- `dd2bb77` audit et documentation de la génération régionale réelle.

## B. Audit du précédent travail

Les 21 fichiers modifiés depuis `20d86ab` ont été examinés : catalogue
d’acquisition avec SHA, collecte explicite, buffer EPSG:2154 par lots sans
simplification, références PBF complètes, sélection OSM après assemblage des
aires, audit des objets exclus et publication atomique. Le validateur GeoJSON
consomme toujours toute la collection. Les tests conservent Cassis et empêchent
la publication de générations incomplètes. Aucun jeu régional ajouté aux bundles.

Les profondeurs SHOM gardent leur masque NoData, leur source et leur référence
verticale. Le buffer régional reste 30 NM, Corse exclue. Aucune nouvelle collecte
ni génération nécessaire : la génération publiée est valide et inchangée.

Incomplet : ce travail validait le POC ; `mobile/` était encore l’application
historique. Son README demandait des clés propriétaires, et son manifest Android
n’autorisait Internet qu’en Debug. Une estimation photo sans GPS actuel pouvait
aussi atteindre `_position!` dans le libellé du marqueur ; ce cas est corrigé et testé. La configuration iOS du POC déclarait le réseau
local, sans exceptions explicites par IP/CIDR pour la politique ATS iOS 17+.

Corrections : migration de l’application complète, Internet dans le manifest
principal, HTTP Debug uniquement, exceptions privées/loopback iOS dans le POC
et mobile. Les API de projection du plugin utilisent des pixels physiques sous
Android et des points sous iOS : normalisation testée dans l’adaptateur, sans
modifier les calculs métier du formulaire. Les permissions audio/stockage
inutilisées, héritées des plugins Android, sont retirées du manifest fusionné.

## C. Synchronisation avec dev

Aucun commit dev absent au moment du fetch. Aucun conflit. Authentification,
profils, caméra, estimation, JPEG, formulaire, notifications et haptics gardent
leur code d’origine ; aucun fichier du backend n’est modifié.

## D. Cartographie et serveur réel

Nouvel audit en lecture seule de la génération
`1a8135e5e375494b8a17b428f313e65d` :

- bbox `[2.4, 41.85, 8.3, 44.45]`, center `[5.35, 43.15]`, Corse exclue ;
- littoral réel 1 579,451 km, buffer 55 560 m, zone marine 32 606,080 km² ;
- surface hors bbox : 0 km² ;
- 32 243 objets, SHA des features inchangé
  `c0a76e58f0a329175522e23b65ea2dada421a7dacf58610983ff9655130517da` ;
- OSM Geofabrik, complément OSM officiel et land polygons réels ; SHOM HOMONIM ;
- 96,247086 % de cellules bathymétriques connues ; 122 368 cellules NoData,
  environ 1 223,68 km², surtout à l’est du domaine SHOM ; aucune profondeur créée.

Le [rapport cartographique détaillé](../cartography/FRANCE_MED_VALIDATION.md)
donne les licences, SHA des sources, tailles et limites. Les tests Cassis restent
verts et ses fichiers de référence ne sont pas modifiés.

Le serveur sur 8765 a été interrogé réellement, puis relancé sur `0.0.0.0`
pour accepter les connexions aux interfaces du poste :

| Ressource | HTTP | Octets reçus |
|---|---:|---:|
| `/health` | 200 | 15 |
| `/style.json` (REGION_REAL, 61 couches) | 200 | 31 670 |
| `/data/france_med/manifest.json` | 200 | 23 106 |
| `/data/france_med/water.geojson` | 200 | 17 488 247 |
| `/tiles/vector/france_med/6/32/23.pbf` (gzip) | 200 | 267 725 |
| `/tiles/bathymetry/france_med/7/66/46.png` | 200 | 9 014 |
| `/tiles/bathymetry/france_med/9/0/0.png` | 204 | 0 |

Le même serveur répond au header `Host: 192.168.1.50:8765` avec toutes ses
ressources locales à cette adresse, sans localhost. Cette vérification teste
les URLs générées ; elle ne prouve pas l’accessibilité réseau depuis un téléphone.
Le relief externe conserve son HTTPS existant. Le code du serveur n’a pas changé.
L’accès par `http://172.17.58.32:8765/style.json` (interface WSL actuelle) a aussi
été vérifié depuis ce poste. L’accès d’un téléphone au réseau WSL NAT exige le
routage/port forwarding approprié ; il n’a pas été testé depuis un téléphone.

## E. Migration Flutter mobile

Dépendance finale : `maplibre_gl` **0.27.1**, identique au POC.
Aucun SDK, jeton ou style propriétaire nécessaire à l’affichage.
`NOWAVE_STYLE_URL` n’a pas de loopback implicite dans mobile. URL HTTP(S)
configurable ; HTTPS obligatoire en Release ; style v8 et provenance réelle
vérifiés avant création du moteur natif.

Fichiers : `main.dart`, `core/map/map_config.dart`, nouvel adaptateur
`core/map/map_controller.dart`, nouvelle vue `core/map/map_view.dart`,
`features/map/presentation/map_screen.dart`, pubspec/lock et exemple `.env`.

Équivalences :

| Fonction antérieure | Fonction actuelle |
|---|---|
| Caméra/viewport animé | `CameraPosition`, `moveCamera` / `animateCamera` |
| Follow automatique | Flux Geolocator → adaptateur ; arrêté au geste |
| Nord/cap/rotation au doigt | Bearing explicite, cap partagé actualisé |
| Conversion pixels/coordonnées | `toLatLng` / `toScreenLocation`, unités normalisées |
| Padding sous formulaire | `updateContentInsets` en points logiques |
| Tilt en édition | Widget MapLibre : tilt désactivé, caméra à plat |
| Flèche 3D | Overlay Flutter 44 points à la position projetée, cap moins bearing |
| Attribution | Attribution du style, remontée à droite pendant l’édition |
| Erreur de style/réessai | HTTP/JSON contrôlés, timeout 30 s, recréation du moteur |

Différences voulues : flèche 2D au lieu de 3D ; ouverture régionale France
Méditerranée avant le premier GPS ; heading-up actualisé en continu.
La carte conserve zoom initial utilisateur 14, restauration caméra/suivi,
marker fixe/relevé, notices, haptics, abandon, callback caméra et correction
sur l’estimation. Le GPS ne déplace pas la caméra pendant le formulaire.
Une projection fraîche est demandée avant de publier.

Le JPEG, les mesures figées, `PhotoReportDraft`, l’estimation, les requêtes
avec token Firebase, l’identifiant idempotent et le retry de l’upload restent
ceux de dev. Les tests utilisent maintenant l’écran entier avec un adaptateur
simulé, et pas le widget du SDK natif.

## F. Android

Builds de **mobile/** exécutés avec le JDK 21 complet, SDK compile/target 36,
minimum SDK effectif 24 : Debug et Release ARM64 séparé, réussis.
Commandes sans backend configuré (validation de compilation uniquement) :

```bash
cd mobile
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH \
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=NOWAVE_STYLE_URL=http://127.0.0.1:8765/style.json
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:$PATH \
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --dart-define=NOWAVE_STYLE_URL=https://cartes.nowave.example/style.json
```

L’adresse HTTPS ci-dessus est un exemple pour compiler, pas un serveur déployé.
Aucun `.env.json` local n’était présent ; pour un parcours authentifié, reconstruire
avec les adresses réelles comme décrit dans [README.md](README.md).
Les APK ne contiennent aucun MBTiles/PBF régional/TIFF/GLB ni SDK propriétaire.
Le Release contient uniquement les bibliothèques ARM64 ; le plugin ajoute aussi
ses ABIs à l’APK Debug universel. Cleartext vérifié dans les manifests fusionnés :
true en Debug, false en Release. Caméra/GPS/notifications conservés ; aucune
permission micro/stockage dans les manifests fusionnés. Pas de GPS en arrière-plan.

`adb devices -l` : aucun appareil. Aucun login, rendu natif, capture, calibration
ou publication physique validé. Signing Release : clé Debug héritée du projet.
Les plugins app_settings/firebase_core/firebase_auth produisent l’avertissement
Flutter sur KGP ; les builds actuels réussissent sans modification de ces plugins.

## G. iOS

**BUILD IOS NON EXÉCUTÉ — RAISON : macOS + Xcode requis.**
Le Podfile est absent car le projet utilise déjà SwiftPM. Audit du workspace,
project, scheme, xcconfig, plist, Firebase et des packages natifs résolus :

| Dépendance | Résolution / iOS minimum natif |
|---|---|
| MapLibre | 0.27.1, Native 6.28.0 / 13 |
| geolocator | 14.0.3, geolocator_apple 2.3.14 / 11 |
| camera | 0.12.1, camera_avfoundation 0.10.3 / 13 |
| precise_compass | 0.2.0 / 12 |
| sensors_plus | 7.1.0 / 13 |
| firebase_core/auth/messaging | 4.15.0 / 6.7.0 / 16.7.0, Firebase 12.19.0 / 15 |
| app_settings | 9.0.0 / 13 |
| package_info_plus (transitif) | 10.2.1 / 13 en SwiftPM |
| image/http/http_parser/uuid/cupertino_icons | Dart/UI, aucun plugin iOS ajouté |

Tous les dix plugins iOS possèdent un `Package.swift` ; iOS 15 du projet couvre
leurs minima. Les pins propriétaires de l’ancien moteur sont retirés ; Xcode
résoudra le package MapLibre exact lors du premier build Mac.
Caméra, localisation, mouvement, notifications et APNs sont configurés ; réseau
local et ATS privés uniquement en Debug. Aucun micro/photothèque inutile.
API Dart commune pour projection, caméra, gestures et overlays ; pas de logique
ADB/Java/chemin Android essentielle à l’application.

Les [commandes exactes pour Vadim](IOS_TESTING.md) couvrent checkout,
clean/pub get, SwiftPM (pod install seulement si Podfile), tests, simulateur,
iPhone LAN/HTTPS, signature et checklist physique.
Les politiques réseau et SwiftPM suivent les documentations
[Apple ATS](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
et [Flutter SwiftPM](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).

## H. Tests

- Baseline mobile avant migration : 95 tests réussis, analyse sans problème.
- Après migration : **111 tests réussis**, aucun test supprimé ou désactivé.
  16 nouveaux tests couvrent URL/provenance/erreurs, unités de projection,
  caméra/suivi/gestures/orientation, refus GPS, manuel/photo/correction/upload,
  idempotence, abandon et restauration.
- `flutter pub get`, `flutter analyze`, `flutter test` : mobile et POC réussis.
- POC : **8 tests réussis**, analyse sans problème.
- Cartographie : **44 tests Python réussis** (42 existants + deux tests de
  configuration mobile complète et Host LAN), sans skip.
- npm : **5 profils MapLibre v8 valides** ; le style réel servi a 61 couches.
- `bash -n cartography/tools/build_vector_tiles.sh` et `git diff --check` : réussis.
- Audit en lecture seule : SHA/features/couverture/NoData inchangés.

## I. Livraison Git

Fichiers modifiés / ajoutés pendant cette passe :

- moteur : `mobile/lib/main.dart`, `mobile/lib/core/map/map_config.dart`,
  `mobile/lib/core/map/map_controller.dart`, `mobile/lib/core/map/map_view.dart`,
  `mobile/lib/features/map/presentation/map_screen.dart` ;
- dépendances/configuration : `mobile/pubspec.yaml`, `mobile/pubspec.lock`,
  `mobile/.env.example.json` ;
- Android : `mobile/android/app/build.gradle.kts`,
  `mobile/android/app/src/main/AndroidManifest.xml`,
  `mobile/android/app/src/debug/AndroidManifest.xml` ;
- iOS : `mobile/ios/Runner/Info.plist`, `mobile/ios/Runner/Info-Debug.plist`,
  `mobile/ios/Runner.xcodeproj/project.pbxproj`,
  `mobile/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
  `map_poc/ios/Runner/Info-Debug.plist` ;
- tests : `mobile/test/core/map/map_config_test.dart`,
  `mobile/test/features/map/presentation/map_screen_test.dart`,
  `cartography/tests/test_mobile_config.py` ;
- docs : `mobile/README.md`, `mobile/IOS_TESTING.md`,
  `mobile/MAPLIBRE_VALIDATION.md`, `map_poc/README.md`.

Modifications regroupées en commits moteur/écran, configuration native et réseau,
régression, puis documentation. La branche feat seule est destinée au push ;
aucun changement sur dev, aucun reset, rebase ou force-push.
Les données externes, APK, logs et rapports temporaires ne sont pas ajoutés à Git.
Les SHA finaux et l’état distant figurent dans le rapport de livraison.

## J. Limites restantes constatées

1. Build iOS et parcours sur téléphones Android/iPhone non exécutés.
2. Backend local sans route `POST /api/v1/reports/{id}/photo` : publication et
   retry client testés avec réponses simulées ; aucun upload réel validé.
3. Les adresses de backend et de cartes doivent être configurées par le testeur.
   Le serveur cartographique et ses données ne sont pas déployés par cette tâche.
4. MapLibre 0.27.1 n’expose pas de callback Dart d’erreur de chaque ressource
   native après chargement du style. Les erreurs HTTP/JSON initiales et le délai
   de chargement affichent Réessayer ; les erreurs ultérieures d’une tuile
   individuelle restent gérées/journalisées par le SDK. À contrôler sur appareil.
5. NoData SHOM à l’est, précision OSM et terrain externe conservent les limites
   documentées ; water.geojson pèse 17,49 Mo. Aucun offline développé.
6. Signature Android de développement et provisioning/APNs iOS à vérifier par Vadim.
