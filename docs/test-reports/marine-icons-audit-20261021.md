# Audit de la palette maritime NoWave — 21 octobre 2026

> Les sections A–H décrivent l’audit local initial, avant autorisation de publication.
> La section I consigne les validations fraîches de la mission de finalisation.

## Conclusion

Les cinq échecs ont été reproduits, expliqués et corrigés. La suite complète
passe de **647 réussites / 5 échecs** à **656 réussites / 0 échec / 0 ignoré**
(652 tests existants et 4 tests supplémentaires). Deux passes distinctes ont
été réalisées, avec des méthodes de vérification différentes. Aucun commit,
push, merge, rebase, changement de branche du répertoire principal, ni action
Linear n'a été effectué.

La correction essentielle consiste à **transmettre un PNG encodé au pont natif
Mapbox Maps Flutter 2.30.1**, et non des octets RGBA bruts. Les 43 PNG fournis
n'ont pas été retouchés. Les hypothèses anciennes des tests concernant le
marqueur neutre ont été adaptées à son nouveau canevas 72×72, en vérifiant
explicitement sa taille logique inchangée de 4 px.

Réserve visuelle : certains topmarks noirs manquent de contraste sur le fond
nocturne de stress. Le thème de production reste `day`. Ce rapport ne valide
pas tous les thèmes, tous les sites nautiques ou l'exécution sur un appareil iOS.

## A. État Git et environnement

- Branche initiale et finale : `feature/map-marine-icons`.
- SHA de départ, inchangé : `5f86891f3efa63bcc2a1be227bb3ab9f8abfcb13`.
- Référence locale `origin/dev` : `6be2fcc6361be438648fdb8789d6a9e4e941412b`.
- Flutter 3.47.6, Dart 3.13.5, Mapbox Maps Flutter **2.30.1**, sans mise à jour des dépendances.
- Worktree de comparaison détaché : `/tmp/nowave-marine-icons-audit-20261021/dev-worktree`, créé depuis `origin/dev` ; répertoire principal non basculé et modifications locales conservées.
- Téléphone disponible : LGN LX1, Android 15/API 35, `AV5PJV6328H03108`.
- État initial et empreintes conservés : [statut initial](/tmp/nowave-marine-icons-audit-20261021/initial-status.txt), [empreintes initiales](/tmp/nowave-marine-icons-audit-20261021/initial-hashes.json), [diff binaire initial](/tmp/nowave-marine-icons-audit-20261021/initial.diff).

### Modifications déjà présentes à l'ouverture de la mission

41 PNG suivis modifiés (12 bouées et 29 aides fixes), deux nouveaux PNG de
ports/marinas, les trois couches de chargement, `pubspec.yaml` et le helper
`marine_icon_image.dart` non suivi. `docs/design/` et `mobile/codex_photo/`
étaient déjà présents et non suivis ; leurs fichiers ont été préservés.

```text
 M mobile/assets/icons/buoys/east.png
 M mobile/assets/icons/buoys/green.png
 M mobile/assets/icons/buoys/isolated-danger.png
 M mobile/assets/icons/buoys/neutral.png
 M mobile/assets/icons/buoys/north.png
 M mobile/assets/icons/buoys/preferred-port.png
 M mobile/assets/icons/buoys/preferred-starboard.png
 M mobile/assets/icons/buoys/red.png
 M mobile/assets/icons/buoys/safe-water.png
 M mobile/assets/icons/buoys/south.png
 M mobile/assets/icons/buoys/west.png
 M mobile/assets/icons/buoys/yellow.png
 M mobile/assets/icons/fixed-aids/beacon-east.png
 M mobile/assets/icons/fixed-aids/beacon-green-grey.png
 M mobile/assets/icons/fixed-aids/beacon-green-white.png
 M mobile/assets/icons/fixed-aids/beacon-green.png
 M mobile/assets/icons/fixed-aids/beacon-grey-green.png
 M mobile/assets/icons/fixed-aids/beacon-grey-red.png
 M mobile/assets/icons/fixed-aids/beacon-isolated-danger.png
 M mobile/assets/icons/fixed-aids/beacon-north.png
 M mobile/assets/icons/fixed-aids/beacon-preferred-port.png
 M mobile/assets/icons/fixed-aids/beacon-preferred-starboard.png
 M mobile/assets/icons/fixed-aids/beacon-red-grey.png
 M mobile/assets/icons/fixed-aids/beacon-red-white.png
 M mobile/assets/icons/fixed-aids/beacon-red.png
 M mobile/assets/icons/fixed-aids/beacon-safe-water.png
 M mobile/assets/icons/fixed-aids/beacon-south.png
 M mobile/assets/icons/fixed-aids/beacon-west.png
 M mobile/assets/icons/fixed-aids/beacon-white-green.png
 M mobile/assets/icons/fixed-aids/beacon-white-red.png
 M mobile/assets/icons/fixed-aids/beacon-yellow.png
 M mobile/assets/icons/fixed-aids/light-default.png
 M mobile/assets/icons/fixed-aids/light-green.png
 M mobile/assets/icons/fixed-aids/light-red.png
 M mobile/assets/icons/fixed-aids/light-white.png
 M mobile/assets/icons/fixed-aids/light-yellow.png
 M mobile/assets/icons/fixed-aids/lighthouse-default.png
 M mobile/assets/icons/fixed-aids/lighthouse-green.png
 M mobile/assets/icons/fixed-aids/lighthouse-red.png
 M mobile/assets/icons/fixed-aids/lighthouse-white.png
 M mobile/assets/icons/fixed-aids/lighthouse-yellow.png
 M mobile/lib/features/map/data/buoy_layer.dart
 M mobile/lib/features/map/data/fixed_aid_layer.dart
 M mobile/lib/features/map/data/harbour_layer.dart
 M mobile/pubspec.yaml
?? docs/design/
?? mobile/assets/icons/harbours/
?? mobile/codex_photo/
?? mobile/lib/features/map/data/marine_icon_image.dart
```

## B. Les cinq tests initialement échoués

Le journal historique correspondant au résultat annoncé n'a pas été retrouvé.
La nouvelle exécution complète a reproduit exactement **647 réussites et
5 échecs**. Un ancien journal d'une autre validation, à 650 réussites, n'a pas
été utilisé comme preuve de ces cinq échecs.

Pour chaque cas, le test a été relancé séparément avant correction, séparément
sur `origin/dev`, puis séparément après correction. Tous les tests concernés
étaient identiques à ceux de `origin/dev` avant notre intervention.

Fichiers de preuve : [suite initiale](/tmp/nowave-marine-icons-audit-20261021/baseline-tests.log),
[avant](/tmp/nowave-marine-icons-audit-20261021/initial-individual-tests.json),
[comparaison dev](/tmp/nowave-marine-icons-audit-20261021/dev-individual-tests.json),
[avant/après individuels](/tmp/nowave-marine-icons-audit-20261021/before-after-individual-tests.json).

### B.1. `installation concurrente idempotente puis reload du style`

- **Fichier :** `mobile/test/features/map/data/buoy_layer_test.dart`.
- **Pile pertinente :** `TestStyle.addStyleImage`, ligne 80 dans le journal initial → `BuoyLayer._install` → `BuoyLayer.addTo` → installation concurrente.
- **Attendu / obtenu :** Le faux SDK exigeait `scale == 3` pour toutes les images ; valeur reçue : `18.0` pour `nowave-buoy-neutral`.
- **Cause démontrée :** Le nouveau canevas neutre est 72×72 au lieu de 12×12. Le ratio 18 déjà ajouté à l’intégration conserve 72/18 = 4 px logiques, comme 12/3 auparavant. La taille écran était correcte ; l’ancienne attente du test ne l’était plus.
- **Classification :** régression liée à l'intégration locale de la palette ; pour B.1–B.3, il s'agit d'attentes de tests devenues obsolètes après un changement graphique intentionnel, et non d'un agrandissement du neutre. Pour B.4–B.5, le format transmis était réellement incompatible avec le SDK natif.
- **Correction :** Contrôler ratio 18 pour le neutre, 3 pour les autres, dimensions 72×72 et largeur logique 4/24 px. Assertions PNG, nombre d’images, concurrence, source, couches et reload conservées.
- **Résultat :** échec individuel avant (code 1), réussite sur `origin/dev` (code 0), réussite individuelle après (code 0), puis réussite dans la suite finale.
- **Preuves :** [avant](/tmp/nowave-marine-icons-audit-20261021/initial-test-1.log), [dev](/tmp/nowave-marine-icons-audit-20261021/dev-test-1.log), [après](/tmp/nowave-marine-icons-audit-20261021/fixed-test-1.log).

### B.2. `une installation refusée reste retentable`

- **Fichier :** `mobile/test/features/map/data/buoy_layer_test.dart`.
- **Pile pertinente :** `expectLater` → `TestStyle.addStyleImage`, ligne 80 initiale → `BuoyLayer._install`.
- **Attendu / obtenu :** Le test attendait une `PlatformException` provoquée par la source refusée. Il recevait d’abord un `TestFailure` : ratio attendu 3, obtenu 18.0.
- **Cause démontrée :** La même hypothèse obsolète du faux SDK faisait échouer l’ajout d’image avant d’atteindre la panne de source que le test devait exercer.
- **Classification :** régression liée à l'intégration locale de la palette ; pour B.1–B.3, il s'agit d'attentes de tests devenues obsolètes après un changement graphique intentionnel, et non d'un agrandissement du neutre. Pour B.4–B.5, le format transmis était réellement incompatible avec le SDK natif.
- **Correction :** La correction du contrat de taille du faux SDK permet d’exercer réellement la `PlatformException`, puis le réessai. L’assertion de panne n’a pas été supprimée ou assouplie.
- **Résultat :** échec individuel avant (code 1), réussite sur `origin/dev` (code 0), réussite individuelle après (code 0), puis réussite dans la suite finale.
- **Preuves :** [avant](/tmp/nowave-marine-icons-audit-20261021/initial-test-2.log), [dev](/tmp/nowave-marine-icons-audit-20261021/dev-test-2.log), [après](/tmp/nowave-marine-icons-audit-20261021/fixed-test-2.log).

### B.3. `les variantes livrées sont des PNG décodables à densité 3`

- **Fichier :** `mobile/test/features/map/data/buoy_layer_test.dart`.
- **Pile pertinente :** `main` → décodage `ui.instantiateImageCodec` → assertion des dimensions, ligne 418 initiale.
- **Attendu / obtenu :** Largeur neutre attendue : 12 ; obtenue : 72. Le test contrôlait aussi le centre de l’ancien dessin.
- **Cause démontrée :** La palette fournie remplace le neutre par un dessin 72×72. La qualification nautique ne change pas. Son centre réel vaut [13,13,13,255], contre [32,38,44,255] pour l’ancien disque.
- **Classification :** régression liée à l'intégration locale de la palette ; pour B.1–B.3, il s'agit d'attentes de tests devenues obsolètes après un changement graphique intentionnel, et non d'un agrandissement du neutre. Pour B.4–B.5, le format transmis était réellement incompatible avec le SDK natif.
- **Correction :** Vérifier 72×72, centre [13,13,13,255], coins transparents et 72/18 = 4 px logiques. Les contrôles de décodage, dimensions, centre et transparence sont maintenus ; le titre historique du test est conservé pour permettre les mêmes relances individuelles.
- **Résultat :** échec individuel avant (code 1), réussite sur `origin/dev` (code 0), réussite individuelle après (code 0), puis réussite dans la suite finale.
- **Preuves :** [avant](/tmp/nowave-marine-icons-audit-20261021/initial-test-3.log), [dev](/tmp/nowave-marine-icons-audit-20261021/dev-test-3.log), [après](/tmp/nowave-marine-icons-audit-20261021/fixed-test-3.log).

### B.4. `source réelle Z6, images transparentes 3x, reload idempotent`

- **Fichier :** `mobile/test/features/map/data/harbour_layer_test.dart`.
- **Pile pertinente :** `ImageDescriptor.encoded` → `instantiateImageCodecWithSize` → `instantiateImageCodec` → `harbour_layer_test.dart:67`.
- **Attendu / obtenu :** Une image PNG décodable était attendue. Le décodeur levait `Exception: Invalid image data` sur les 20 736 octets RGBA bruts renvoyés par le nouveau helper.
- **Cause démontrée :** Régression réelle de chargement : le helper confondait le contrat générique MbxImage avec le format encodé attendu par les ponts Android et iOS installés.
- **Classification :** régression liée à l'intégration locale de la palette ; pour B.1–B.3, il s'agit d'attentes de tests devenues obsolètes après un changement graphique intentionnel, et non d'un agrandissement du neutre. Pour B.4–B.5, le format transmis était réellement incompatible avec le SDK natif.
- **Correction :** Retourner les octets PNG originaux avec les dimensions lues au décodage. Le test de ports reste entièrement inchangé et réussit.
- **Résultat :** échec individuel avant (code 1), réussite sur `origin/dev` (code 0), réussite individuelle après (code 0), puis réussite dans la suite finale.
- **Preuves :** [avant](/tmp/nowave-marine-icons-audit-20261021/initial-test-4.log), [dev](/tmp/nowave-marine-icons-audit-20261021/dev-test-4.log), [après](/tmp/nowave-marine-icons-audit-20261021/fixed-test-4.log).

### B.5. `images et couches idempotentes, panne retentable et reload`

- **Fichier :** `mobile/test/features/map/data/fixed_aid_layer_test.dart`.
- **Pile pertinente :** `AidStyle.addStyleImage`, ligne 38 initiale → `FixedAidLayer._install` → `FixedAidLayer.addTo`.
- **Attendu / obtenu :** Signature PNG attendue : [137,80,78,71,13,10,26,10]. Reçu : [0,0,0,0,0,0,0,0], début du buffer RGBA transparent.
- **Cause démontrée :** Même régression de format du helper. Une attente de dimension/ratio neutre obsolète était également présente plus loin dans le faux SDK.
- **Classification :** régression liée à l'intégration locale de la palette ; pour B.1–B.3, il s'agit d'attentes de tests devenues obsolètes après un changement graphique intentionnel, et non d'un agrandissement du neutre. Pour B.4–B.5, le format transmis était réellement incompatible avec le SDK natif.
- **Correction :** PNG encodé rétabli ; faux SDK vérifiant ratio 18 et 4 px pour le neutre, ratio 6 et 12 px pour les feux, ratio 3 et 24 px pour balises/phares. Assertions sur signature, couches, panne et reload conservées.
- **Résultat :** échec individuel avant (code 1), réussite sur `origin/dev` (code 0), réussite individuelle après (code 0), puis réussite dans la suite finale.
- **Preuves :** [avant](/tmp/nowave-marine-icons-audit-20261021/initial-test-5.log), [dev](/tmp/nowave-marine-icons-audit-20261021/dev-test-5.log), [après](/tmp/nowave-marine-icons-audit-20261021/fixed-test-5.log).

Les messages `API_BASE_URL`, `setStyleImportConfigProperty` non implémenté et
`FCM indisponible` observés dans les tests de parcours/faux services ne sont
pas les exceptions responsables de ces cinq échecs. Aucune correction du
backend, de Firebase ou de la configuration privée n'a été faite pour les faire disparaître.

## C. Première passe d'audit

1. **Inventaire et intégrité des fichiers** : 43 PNG 72×72 avec transparence,
   pixels opaques et partiellement transparents, coins transparents. Signature
   PNG, CRC de tous les chunks, dimensions et décodage vérifiés. Les 43 empreintes
   correspondent exactement au paquet fourni dans `/tmp/nowave_marine_palette/`.
2. **Contrat réel du SDK** : lecture du code installé et de sa version verrouillée.
   `StyleController.kt:683` appelle `BitmapFactory.decodeByteArray`, puis copie les
   pixels dans le buffer natif. `StyleController.swift:300` utilise `UIImage(data:)`.
   Le nouveau buffer `rawRgba` devait donc être remplacé par le PNG encodé.
3. **Ratios** : 72/3 = 24 px pour bouées qualifiées, balises et phares ;
   72/6 = 12 px pour feux ; 72/18 = 4 px pour les deux références neutres ;
   ports/marinas à 72/3 = 24 px. Les interpolations de zoom restent inchangées.
4. **Règles nautiques et affichage** : comparaison intégrale des méthodes de
   sélection d'images, filtres, zooms, priorités et collisions avec `origin/dev`.
   Identité confirmée : aucune modification des règles IALA A/B, classifications,
   coordonnées, sources ou hiérarchie des aides.
5. **Chargement, concurrence et erreurs** : cache d'images par instance pour
   bouées/aides fixes, vérification du style courant à chaque installation,
   enregistrements répétés après reload, erreurs propagées et installation
   retentable. Les tests de pannes de source/couche restent exécutés.
6. **Documentation** : les README décrivaient encore l'ancien neutre 12×12,
   les anciens dessins et leurs générateurs. Ils ont été mis en accord avec la
   nouvelle palette, en conservant les références historiques.

Preuves : [inventaire](/tmp/nowave-marine-icons-audit-20261021/asset-inventory-pass1.json),
[CRC et comparaison source](/tmp/nowave-marine-icons-audit-20261021/asset-crc-source-pass1.json),
[planche des fichiers réellement présents](/tmp/nowave-marine-icons-audit-20261021/asset-contact-pass1.png),
[contrat SDK installé](/tmp/nowave-marine-icons-audit-20261021/installed-sdk-contract.json),
[règles métier](/tmp/nowave-marine-icons-audit-20261021/business-rules-pass1.json),
[tests ciblés : 19 réussites](/tmp/nowave-marine-icons-audit-20261021/focused-fix-pass1.log).

Références du contrat : [pont Android installé](/home/palms/.pub-cache/hosted/pub.dev/mapbox_maps_flutter-2.30.1/android/src/main/kotlin/com/mapbox/maps/mapbox_maps/StyleController.kt:683),
[pont iOS installé](/home/palms/.pub-cache/hosted/pub.dev/mapbox_maps_flutter-2.30.1/ios/mapbox_maps_flutter/Sources/mapbox_maps_flutter/Classes/StyleController.swift:300),
[formats d’octets Flutter et prémultiplication](https://api.flutter.dev/flutter/dart-ui/ImageByteFormat.html).

## D. Deuxième passe d'audit indépendante

Cette passe n'a pas simplement repris la première liste de conclusions :

- **Autre décodeur et contrat complet** : tests via `dart:ui`/le moteur Flutter,
  au lieu du décodeur Dart `package:image` utilisé pour l'inventaire. Vérification
  des 43 assets du manifeste compilé, des octets PNG réellement transmis, des
  dimensions et de tous les pixels RGBA prémultipliés après décodage.
- **Références effectives** : collecte récursive des identifiants dans les
  expressions réelles des trois couches et comparaison au manifeste. Résultat :
  43 fichiers, 44 identifiants (le 44e est l'alias `nowave-beacon-neutral`),
  aucune référence orpheline ni catégorie perdue.
- **Cas adverses du helper** : image à alpha 128 donnant [100,50,25,128]
  après décodage ; `ByteData` avec décalage non nul ; asset absent ; PNG corrompu ;
  nouvel essai réussi. Aucune exception de ces tests n'est ignorée.
- **Réexécution indépendante des règles existantes** : tests IALA A/B et bandes
  bicolores, seuils, priorité, collisions, idempotence et reload ; 23 tests
  ciblés réussis en incluant les quatre nouveaux tests.
- **Contrôle natif Android réel** : galerie temporaire avec données GeoJSON
  synthétiques, sans GPS, Firebase ni backend réel. Les vraies classes
  `BuoyLayer`, `FixedAidLayer` et `HarbourLayer` enregistrent leurs images dans
  le SDK Mapbox natif. Les 43 PNG sont relus dans le style ; leurs 20 736 octets
  RGBA prémultipliés natifs sont contrôlés. 43 symboles sont interrogés dans le
  rendu écran. L'alias neutre est présent.
- **Deux rechargements réels** : passage 2 sur fond sombre puis passage 3 sur
  fond clair : chaque fois 43 assets, 44 identifiants et 43 symboles rendus.
  Les 86 relectures natives satisfont les contrôles d'alpha et de prémultiplication.
- **Retour à l'application normale** : recompilée et relancée sur le même
  téléphone ; les nouveaux pictogrammes apparaissent sur la carte maritime
  réelle, avec la flèche de localisation existante.
- **Recherche de problèmes introduits par la correction** : trois remarques
  de lint dans le nouveau fichier de tests ont été corrigées (import superflu,
  deux blocs sans accolades), puis `flutter analyze` a été relancé avec succès.

### Divergences résolues

La documentation générique de `MbxImage.data` indique RGBA brut, tandis que
`addStyleImage` attend un PNG dans ces ponts natifs précis. Le test natif confirme
le choix du PNG ; on ne généralise pas ce contrat à une autre version.

Le premier contrôle du harnais de diagnostic supposait à tort que
`getStyleImage` renvoyait aussi un PNG sur Android. Il renvoie en réalité le
buffer RGBA brut du style. Le harnais **temporaire** a été corrigé pour vérifier
ces pixels directement. Cette asymétrie lecture/écriture a été explicitement
contrôlée, sans modifier ou masquer une exception de l'application.

Sur le plan visuel, le fond clair valide les 43 dessins. Le fond de stress
nocturne réduit le contraste de plusieurs topmarks noirs. Ce point est signalé,
non masqué par une modification opportuniste des dessins ou des règles métier.
L'application reste configurée en thème de jour.

Preuves : [23 tests de la seconde passe](/tmp/nowave-marine-icons-audit-20261021/pass2-contract-and-mapping.log),
[intégrité du périmètre](/tmp/nowave-marine-icons-audit-20261021/pass2-scope-integrity.json),
[résumé natif et 86 relectures](/tmp/nowave-marine-icons-audit-20261021/native-summary.json),
[journal natif intégral](/tmp/nowave-marine-icons-audit-20261021/native-gallery.log),
[fond clair après reload](/tmp/nowave-marine-icons-audit-20261021/native-gallery-light.png),
[fond sombre après reload](/tmp/nowave-marine-icons-audit-20261021/native-gallery-dark.png),
[application normale](/tmp/nowave-marine-icons-audit-20261021/main-app.png).

## E. Corrections réalisées — liste exhaustive de nos interventions

| Fichier | Justification |
| --- | --- |
| `mobile/lib/features/map/data/marine_icon_image.dart` | Le helper déjà présent localement retourne maintenant le PNG encodé original, avec ses dimensions décodées et les vues ByteData correctement bornées ; libération du codec et de l'image conservée. Contrat 2.30.1 documenté. |
| `mobile/lib/features/map/data/buoy_layer.dart` | Imports normalisés et commentaire du neutre clarifié. Le ratio 18 déjà présent est conservé. Aucun changement des expressions nautiques, filtres ou tailles selon le zoom. |
| `mobile/lib/features/map/data/fixed_aid_layer.dart` | Import du helper placé selon les conventions. Le chargement commun utilise le helper corrigé ; règles IALA et positionnement inchangés. |
| `mobile/lib/features/map/data/harbour_layer.dart` | Import du helper normalisé. Les deux assets PNG et les catégories déjà branchés sont conservés. |
| `mobile/test/features/map/data/buoy_layer_test.dart` | Ratios, dimensions, taille logique et centre du nouveau neutre contrôlés explicitement ; aucune assertion supprimée et tests de panne/reload conservés. |
| `mobile/test/features/map/data/fixed_aid_layer_test.dart` | Contrôles distincts 4/12/24 px logiques pour neutre/feux/autres aides ; assertion de signature PNG conservée. |
| `mobile/test/features/map/data/marine_icon_image_test.dart` | Quatre tests nouveaux : couverture des identifiants, 43 PNG et pixels après décodage, ByteData décalé et alpha partiel, erreurs puis réessai. |
| `mobile/assets/icons/buoys/README.md` | Dimensions/ratios et format natif actuels ; ancien SVG/générateur identifiés comme historiques. |
| `mobile/assets/icons/fixed-aids/README.md` | 29 dessins, formats, neutre et règles de lecture des bandes documentés sans attribution trompeuse aux anciens générateurs. |
| `mobile/assets/icons/harbours/README.md` | Ajout de la documentation des deux nouveaux assets, de leurs identifiants et de leur ratio. |
| `docs/test-reports/marine-icons-audit-20261021.md` | Présent rapport de revue, preuves et limites. |

Les **43 fichiers PNG et `pubspec.yaml` n'ont pas été changés par cette mission** :
leurs modifications/ajouts appartenaient déjà à l'intégration locale initiale.
Le test `harbour_layer_test.dart` n'a pas été modifié ; sa réussite après correction
est un contrôle indépendant du vrai décodeur.

Les SHA-256 des fichiers déjà présents sous `docs/design/` et
`mobile/codex_photo/` sont identiques avant/après. Aucun de ces fichiers n'a été
supprimé ou ajouté. GPS, boussole, flèche orange, backend et dépendances restent
inchangés. Les scripts et journaux de diagnostic sont conservés sous `/tmp/nowave-marine-icons-audit-20261021`.

## F. Validation finale

| Contrôle | Résultat |
| --- | --- |
| Suite initiale complète | 652 tests : 647 réussis, 5 échoués, 0 ignoré |
| Cinq tests individuels avant | 5 échecs reproductibles |
| Mêmes cinq tests sur `origin/dev` | 5 réussites |
| Cinq tests individuels après | 5 réussites |
| Première vérification ciblée après correction | 19 réussites |
| Seconde passe, mapping et contrat inclus | 23 réussites |
| `dart format --output=none --set-exit-if-changed lib/features/map/data/` | Code 0, aucun fichier à reformater |
| `flutter analyze` | Code 0, `No issues found!` |
| `flutter test --reporter expanded` | **656 réussis, 0 échoué, 0 ignoré ; code 0** |
| Build et exécution Android | Réussis pour la galerie native et l'application normale |
| `git diff --check` | Propre |

Les quatre tests supplémentaires expliquent 652 → 656. Aucun test n'a été
ignoré, désactivé ou retiré ; aucune assertion de panne, collision, qualification,
transparence ou rechargement n'a été neutralisée.

Preuves : [format](/tmp/nowave-marine-icons-audit-20261021/final-format.log),
[analyse](/tmp/nowave-marine-icons-audit-20261021/final-analyze.log),
[suite finale complète](/tmp/nowave-marine-icons-audit-20261021/final-tests.log),
[résumé et codes de sortie](/tmp/nowave-marine-icons-audit-20261021/validation-summary.json),
[exécution normale Android](/tmp/nowave-marine-icons-audit-20261021/main-app.log).

## G. État de la palette maritime

- **Présente :** 43 PNG vérifiés ; 12 bouées, 19 balises, 5 phares, 5 feux, 2 ports/marinas.
- **Déclarée :** trois répertoires présents au manifeste Flutter compilé ; 43 noms attendus.
- **Chargée :** vrais chargements d'assets et enregistrements natifs Android ; 44 identifiants, dont un alias neutre réutilisant le même fichier.
- **Technique :** formats encodés à l'entrée, pixels RGBA prémultipliés après décodage et relecture native, tailles et ratios vérifiés ; erreurs et reloads testés.
- **Visuelle :** 43 pictogrammes inspectés dans une galerie native Mapbox sur Android clair/sombre, puis contrôle de la carte normale. La galerie utilise une échelle de démonstration pour rendre les variantes inspectables ; les ratios de production et leur interpolation sont vérifiés séparément par les tests.
- **IALA :** mappings, classifications, filtres et priorités identiques à `origin/dev` ; assertions IALA A/B et bandes bicolores exécutées avec succès. Les dessins sont des pictogrammes abstraits ; aucun secteur lumineux géographique n'a été calculé.
- **Limite :** pas de contrôle physique iOS, ni de vérification sur le terrain des 43 catégories à toutes les échelles et sur toutes les zones géographiques.

### Inventaire des 43 fichiers

| Asset | Dimensions | Ratio natif | Canevas logique à échelle 1 |
| --- | --- | --- | --- |
| `assets/icons/buoys/east.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/green.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/isolated-danger.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/neutral.png` | 72×72 | 18 | 4 px |
| `assets/icons/buoys/north.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/preferred-port.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/preferred-starboard.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/red.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/safe-water.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/south.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/west.png` | 72×72 | 3 | 24 px |
| `assets/icons/buoys/yellow.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-east.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-green-grey.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-green-white.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-green.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-grey-green.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-grey-red.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-isolated-danger.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-north.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-preferred-port.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-preferred-starboard.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-red-grey.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-red-white.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-red.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-safe-water.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-south.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-west.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-white-green.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-white-red.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/beacon-yellow.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/light-default.png` | 72×72 | 6 | 12 px |
| `assets/icons/fixed-aids/light-green.png` | 72×72 | 6 | 12 px |
| `assets/icons/fixed-aids/light-red.png` | 72×72 | 6 | 12 px |
| `assets/icons/fixed-aids/light-white.png` | 72×72 | 6 | 12 px |
| `assets/icons/fixed-aids/light-yellow.png` | 72×72 | 6 | 12 px |
| `assets/icons/fixed-aids/lighthouse-default.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/lighthouse-green.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/lighthouse-red.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/lighthouse-white.png` | 72×72 | 3 | 24 px |
| `assets/icons/fixed-aids/lighthouse-yellow.png` | 72×72 | 3 | 24 px |
| `assets/icons/harbours/marina.png` | 72×72 | 3 | 24 px |
| `assets/icons/harbours/port.png` | 72×72 | 3 | 24 px |

Le fichier `buoys/neutral.png` sert aussi à `nowave-beacon-neutral` avec ratio 18.
La taille finale à l'écran applique ensuite les interpolations de zoom déjà
existantes, qui n'ont pas été modifiées.

## H. Points restant à traiter et périmètre de la conclusion

1. **Contraste nocturne** : décision graphique à prendre avant d'ajouter un
   thème de nuit en production. Les topmarks noirs de la palette perdent du
   contraste sur le fond sombre de stress ; les PNG fournis n'ont pas été
   retouchés pour masquer ce point. Ce n'est pas un blocage de chargement du
   thème de jour actuel.
2. **iOS physique** : le pont 2.30.1 a été relu et exige bien un PNG, mais aucun
   téléphone/simulateur iOS n'a été exécuté ici. Ne pas assimiler la validation
   Android à une recette matérielle iOS.
3. **Version SDK** : recontrôler le contrat réel `addStyleImage`/`getStyleImage`
   lors d'une future mise à jour ; aucune dépendance n'a été mise à jour ici.
4. **Publication** : les modifications restent locales, prêtes pour revue.
   Aucun commit/push/merge n'a été réalisé. Le worktree `origin/dev` et les
   preuves temporaires sont conservés, sans suppression de fichiers non suivis.

Il ne reste **aucun échec de test inexpliqué**. La validation technique de cette
intégration est établie dans le périmètre testé ; les réserves visuelles et
matérielles ci-dessus restent explicites. La mission s'arrête à ce rapport.

### État final conservé

[Statut Git final](/tmp/nowave-marine-icons-audit-20261021/final-git-status.txt), [statistiques du diff](/tmp/nowave-marine-icons-audit-20261021/final-git-stat.txt), [fichiers réellement changés pendant cette mission](/tmp/nowave-marine-icons-audit-20261021/files-changed-by-this-mission.json).


## I. Revalidation avant publication dans la PR #113

La mission suivante autorise explicitement commit, push normal et mise à jour de
la PR existante. Les mentions « aucun commit/push » ci-dessus décrivent la fin
de l’audit initial, et non le statut de publication ultérieur.

Deux passes fraîches ont été effectuées le 21 octobre 2026 :

1. `flutter analyze` : code 0 ; `flutter test --reporter expanded` :
   **656 tests réussis, aucun échec**.
2. Relecture indépendante du diff et contrôle des 43 PNG (signature, tous les
   CRC, dimensions 72×72, canal alpha), comparaison byte à byte avec `origin/dev`
   des règles de sélection, filtres et zooms des trois couches ;
   `dart format --output=none --set-exit-if-changed lib test` :
   **196 fichiers, aucun changement** ; les trois suites ciblées passent
   **21 tests**. `git diff --check` ne signale aucune erreur.

Les preuves fraîches sont conservées localement dans
`/tmp/nowave-pr113-finalization-20261021/` (`A-analyze.log`, `A-tests.log`,
`A-format.log`, `A-focused.log`, `A-independent-assets.json`).
La preuve Android native des sections précédentes reste une preuve de l’audit
initial ; aucun nouveau test physique iOS n’est revendiqué.

Périmètre de publication : uniquement les trois dossiers de pictogrammes, les
quatre fichiers de chargement, `pubspec.yaml`, les trois fichiers de tests et
ce rapport. `docs/design/` et `mobile/codex_photo/` restent exclus.
La CI distante et le suivi Linear sont documentés dans la PR #113 ; les
correctifs de dépendances sont isolés dans une autre branche et une autre PR.
