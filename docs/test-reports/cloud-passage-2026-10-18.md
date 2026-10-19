# NoWave — traversée des nuages autour de Z5

## État de la validation

Implémentation installée et recette visuelle réalisée sur le LGN LX1 après
confirmation explicite de sa disponibilité. Tests du 18 octobre, terminés dans
la nuit du 18 au 19 octobre 2026 (Europe/Paris). Les limites de mesure de
performance et de disponibilité des services marins sont détaillées ci-dessous.

Branche : `feature/marine-bathymetry` ; HEAD de départ : `d78f2563`.
Aucun commit, push ou PR. La photo et les archives SHOM non suivies sont conservées.

## Inspection et choix technique

Inspection de `globe_style.dart`, `globe_presentation.dart`, `map_screen.dart`,
des événements caméra, de la réduction des animations, des textures et de leur
outil de préparation. La photo `/home/palms/NoWave/3d-rendering-planet-earth.jpg`
a été réellement rouverte et examinée, ainsi que le quadrant nuageux NASA.

Le SDK installé est Mapbox Flutter 2.30.1. Ses rasters restent drapés sur la
surface du globe ; aucune API volumétrique Flutter appropriée n'est exposée.
Une composition Flutter de premier plan permet donc d'ajouter une sensation de
traversée sans modifier le moteur, les sources ni les nuages géographiques.
Voir [comportement des couches Mapbox](https://docs.mapbox.com/flutter/maps/guides/styles/work-with-layers/).

## Effet implémenté

Trois plans de profondeur, six bancs nuageux, trois textures distinctes et des
marges transparentes irrégulières. Les bancs grossissent suivant des lois
exponentielles différentes et s'écartent d'un point de fuite commun. Des décalages
liés aux coordonnées, au cap et à l'inclinaison ajoutent de la parallaxe.
Chaque plan possède sa propre courbe douce d'entrée et de dissipation.

| Zoom | Comportement |
|---|---|
| ≤ 4,5 | Aucun premier plan ajouté. |
| 4,5–4,9 | Approche, premiers bancs distants. |
| 4,9–5,4 | Chevauchement des trois plans, agrandissement et densité maximale décalés. |
| 5,4–6,2 | Les bancs proches s'agrandissent et se dissipent. |
| ≥ 6,2 | Aucun pixel de transition, y compris après un zoom rapide. |

La caméra réelle pilote tout le rendu : aucun timer, ticker, AnimationController
ou animation différée n'est ajouté. Une même caméra donne le même rendu, dans
les deux sens. À l'arrêt, le dessin reste fixe. Un saut direct de Z4 à Z7
n'entraîne pas de traversée rejouée après coup.

Il s'agit d'une illusion de profondeur par plans texturés, pas d'une simulation
volumétrique ni d'une représentation de la météo locale. Les nuages géographiques
existants restent séparés et inchangés.

## Texture et ressources

L'atlas `cloud-passage-atlas.png` contient trois bancs 512 × 512, soit 1536 × 512
au total (747 716 octets PNG ; 3 Mio RGBA, hors copies internes). Il est dérivé de la même mosaïque
NASA Blue Marble dont l'empreinte SHA-256 est vérifiée par l'outil. Le contraste,
les marges transparentes et l'éclairage diffus sont préparés hors application.
Les crédits NASA existants s'appliquent ; aucune nouvelle source payante ni API.

Un seul décodage asynchrone par écran. Six dessins d'image au maximum, avec
filtrage bilinéaire et découpage au viewport. Pas de flou plein écran, de
BackdropFilter, de shader personnalisé, de saveLayer ou de moteur supplémentaire.
Le CustomPainter écoute le contrôleur et repeint sans reconstruire l'écran ni
refaire son layout. Les notifications inutiles sont évitées hors de la fenêtre
et lorsque la caméra ne change pas. Un RepaintBoundary isole ce premier plan.
Voir [CustomPainter et repaint](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html).

Le widget respecte `disableAnimations` et le signal iOS `reduceMotion` : l'effet
décoratif est alors entièrement désactivé, même en cours d'affichage. Il est placé
sous les contrôles, dans IgnorePointer et ExcludeSemantics. Aucune interception
des gestes ou des boutons.

## Fichiers

- `mobile/lib/core/map/cloud_passage_controller.dart` : caméra, fenêtre et courbes des trois plans.
- `mobile/lib/features/map/presentation/widgets/cloud_passage.dart` : décodage, accessibilité et dessin.
- `mobile/lib/features/map/presentation/map_screen.dart` : transmission de la caméra, montage et destruction du composant.
- `mobile/assets/globe/cloud-passage-atlas.png` et `cloud-passage-provenance.json` : nouvelles textures et provenance.
- `mobile/assets/globe/README.md` : documentation des dérivés NASA de premier plan.
- `mobile/tool/prepare_cloud_passage.py` : préparation reproductible de l'atlas.
- `mobile/test/core/map/cloud_passage_controller_test.dart` et `mobile/test/features/map/presentation/widgets/cloud_passage_test.dart`.
- Le présent rapport. Les preuves sont dans `test-results/cloud-passage-2026-10-18/`, ignoré par Git.

## Tests automatisés

```text
dart format --output=none --set-exit-if-changed lib test : OK
flutter analyze --no-pub : No issues found
flutter test --no-pub : 531 tests passed
flutter build apk --debug --no-pub --dart-define-from-file=.env.json : OK
```

Les cinq tests ajoutés couvrent les bornes, l'absence de notifications au repos,
les sauts rapides, le retour arrière, les trois plans distincts, la douceur aux
bornes, les pixels réellement produits par l'atlas, les ouvertures transparentes,
la variation des densités, la disparition totale, le déterminisme du retour,
la continuité du cap à 0°/360°, la variation entre régions, les gestes, les
contrôles et la réduction des animations.

Les rendus isolés du painter ont servi au réglage local ; ils ne sont pas des
captures Android et ne sont pas utilisés comme preuve de validation réelle.

## Conservation du globe et des données

Le style satellite, le halo jaune, l'atmosphère, les étoiles, la Lune, la
bathymétrie, le masque côtier, les courbes, sondes, balises, ports, signalements,
GPS et API_BASE_URL ne sont pas modifiés. Les empreintes des fichiers existants
sont enregistrées dans `test-results/cloud-passage-2026-10-18/preserved-before.sha256`.
Aucun fichier backend, `.env.json`, pubspec ou dépendance modifié.

## Recette Android réelle

Appareil : LGN LX1, `AV5PJV6328H03108`, écran 720 × 1610. Installation par mise
à jour, sans désinstallation de NoWave, effacement des données ni déconnexion
du compte. Les captures brutes proviennent d’`adb exec-out screencap`, les vidéos
de `screenrecord`. Les planches regroupent uniquement des captures réelles.

### Matrice des zooms

Les **16 positions demandées** ont été contrôlées : Z4, Z4,7, Z5, Z5,3, Z5,6,
Z6, Z6,3 et Z7, dans les deux régions suivantes :

- Méditerranée, centre 6° E / 41° N :
  [planche complète](../../test-results/cloud-passage-2026-10-18/contact-med.jpg),
  [traversée Z5,3](../../test-results/cloud-passage-2026-10-18/android-med-z5.3.png),
  [sortie Z6,3](../../test-results/cloud-passage-2026-10-18/android-med-z6.3.png).
- Bahamas, centre 76° O / 24° N :
  [planche complète](../../test-results/cloud-passage-2026-10-18/contact-bahamas.jpg),
  [traversée Z5,3](../../test-results/cloud-passage-2026-10-18/android-bahamas-z5.3.png),
  [carte Z7](../../test-results/cloud-passage-2026-10-18/android-bahamas-z7.0.png).

Les positions natives effectives sont enregistrées dans `android-camera-matrix.json`.
Les coordonnées affichées dans le cartouche de l’application restent celles du
GPS, conformément à son comportement existant ; elles ne désignent pas le centre
caméra des scènes Bahamas.

Constat esthétique : des filaments et masses irrégulières laissent des ouvertures
sur la mer et les côtes. Les bancs s’agrandissent à des vitesses différentes et
sortent du champ pendant que les autres plans deviennent visibles. Les cartes
retrouvent leur lisibilité à la sortie. Aucun rectangle opaque, voile uniforme,
répétition en carrelage ou clignotement observé sur les séquences examinées.
Le rendu est une traversée douce par bancs, avec des zones volontairement ouvertes.

### Mouvement et gestes

- [Vidéo Méditerranée](../../test-results/cloud-passage-2026-10-18/transition-med.mp4) :
  caméra native Z4 → Z7 en 4,5 s, retour en 4,5 s, aller-retour rapide en 300 ms,
  arrêt à Z5,3 puis sortie. Aucun effet différé ne continue après le zoom rapide.
- [Vidéo Bahamas](../../test-results/cloud-passage-2026-10-18/transition-bahamas.mp4) :
  même séquence dans l’autre région.
- [Pincement à deux doigts](../../test-results/cloud-passage-2026-10-18/pinch-real.mp4) :
  véritables événements Android à deux pointeurs injectés par UiAutomation sur
  l’appareil. Le test n’appelle pas `setCamera` pendant le geste. La caméra passe
  de Z4 à **Z6,259**, puis revient à Z3,181. Les valeurs intermédiaires incluent
  Z5,142, Z5,455, Z5,678, puis Z5,634, Z5,287, Z5,069 et Z4,892 au retour.
  La vidéo et `pinch-camera.json` confirment la traversée dans les deux sens.
- Les premières injections très progressives n’amorçaient pas le geste natif.
  Le scénario de test a été corrigé avec une ouverture initiale plus franche,
  suivie d’un déplacement lent. Aucun réglage des gestes de l’application n’a
  été changé. Une injection rapide distincte a traversé Z4–Z5,795 puis est revenue
  à Z3,52 (`pinch-fast-only/`). Les zooms rapides complets Z4–Z7 sont également
  vérifiés par les animations natives ci-dessus.
- Déplacement réel à un doigt au milieu de la traversée : centre passé de 6° E
  à 7,6557591° E à Z5,3 (`pan-at-z5.3.json`).
- Arrêt de trois secondes à Z5,3 : caméra identique et **0 pixel changé sur
  381 600 pixels** de la zone nuageuse contrôlée (x0–720, y650–1180).
  Les seules différences dans une zone plus large proviennent de la pulsation
  GPS existante ; elle ne fait pas partie de ce composant.
- Réduction des animations Android activée en cours d’affichage : le painter
  est retiré et son écouteur désabonné (compteur 0).
  [Capture à Z5,3](../../test-results/cloud-passage-2026-10-18/reduced-motion-z5.3.png).
  Réactivation contrôlée ensuite. Android transmet ici ce signal via
  `TRANSITION_ANIMATION_SCALE`, comme décrit dans
  [l’AccessibilityBridge Flutter](https://chromium.googlesource.com/external/github.com/flutter/engine/+/c9381fb8ef4ca7542cb99b5f668aa9d6415fc7f6/shell/platform/android/io/flutter/view/AccessibilityBridge.java).

### Carte marine, globe et GPS

Le service distant a renvoyé des 429 sur des tuiles marines pendant les essais.
La matrice des zooms et la vidéo Méditerranée utilisent l’API habituelle.
Pour contrôler les détails marins sans masquer cet incident, une compilation
de recette a utilisé temporairement **le même unique API_BASE_URL**, dirigé vers
un proxy local. Celui-ci relaie les routes marines publiques vers le backend
local préexistant sur 8004 et les routes métier vers le service distant.
Aucun fichier de configuration ou backend n’a été modifié. Les requêtes et
leurs statuts sont conservés dans `local-marine-requests.jsonl`.

Contrôles sur cette compilation de recette :

- [Z12 à Toulon](../../test-results/cloud-passage-2026-10-18/marine-local-z12.png) :
  bathymétrie, côte, isobathes, sondes, balises/bouées, infrastructures et
  signalement visibles, sans nuage de premier plan.
- [Z14](../../test-results/cloud-passage-2026-10-18/marine-local-z14.png) :
  sondes et courbes entièrement lisibles, masque côtier conservé.
- Bouton GPS pressé depuis Z5,3 : arrivée native à **Z15,5**, puis déplacement
  libre stable sans rappel automatique au GPS (`marine-gps-proof.json`).
- [Globe spatial](../../test-results/cloud-passage-2026-10-18/globe-unchanged.png) :
  nuages géographiques, atmosphère, étoiles, Lune et halo GPS conservés.

L’APK final est recompilé et réinstallé avec le `.env.json` habituel et l’API
distante. Le téléphone conserve ses données. L’application temporaire de test
est retirée ; les réglages système de veille et d’animations sont restaurés.
Le backend local préexistant reste intact ; seul le proxy créé pour cette recette
est arrêté.

## Mesures de fluidité et limites

Comparaison sur trois allers-retours natifs Z4–Z7 de 1,8 s par trajet après
échauffement du cache. APK debug, appareil réel, aucun enregistrement vidéo
pendant la mesure. Les timings Flutter viennent du VM Service, pas d’une
estimation à partir de la vidéo.

| Mesure Flutter | Premier plan désactivé | Premier plan actif |
|---|---:|---:|
| Trames raster présentes dans l’extrait de trace | 211 | 310 |
| Raster médian | 3,864 ms | 3,591 ms |
| Raster p90 | 4,277 ms | 4,558 ms |
| Raster p99 | 5,811 ms | 15,433 ms |
| Raster > 16,667 ms | 0 | 2 |
| BeginFrame p90 | 0,993 ms | 4,486 ms |
| BeginFrame > 16,667 ms | 0 | 0 |

Le coût du dessin reste compatible avec le budget de 16,7 ms sur la très grande
majorité des trames observées, avec quelques retards de soumission GPU. Les traces
circulaires ne contiennent pas toutes les trames de toute la séquence ; les
nombres ci-dessus décrivent uniquement les extraits conservés. Fichiers :
`foreground-off-timeline-summary.json`, `foreground-on-timeline-summary.json`
et traces complètes correspondantes.

Les compteurs Android `gfxinfo` demandent de la prudence : leur nombre de trames
change fortement avec la composition Flutter/Mapbox (414 sans premier plan,
1247 avec). Sur cette comparaison, leurs p90/p95/p99 sont identiques
(32/42/61 ms), alors que leurs taux « janky » diffèrent (15,46 % / 24,54 %).
Une première comparaison avec l’ancien APK était également moins favorable
(17,46 % / 27,92 %). Ces résultats bruts sont conservés ; ils ne permettent pas
de promettre une absence absolue de coût ni un nombre de FPS constant.

Aucune longue immobilisation ou file d’animation persistante observée sur les
séquences. **Le composant a un coût mesuré et quelques trames dépassent le
budget ; une garantie « zéro baisse de FPS » en production n’est pas établie.**
Un benchmark release prolongé et une recette iOS restent à faire. La mémoire
3 Mio concerne l’atlas décodé seul, pas la mémoire totale du moteur ou du GPU.
La météo est décorative et fixe ; aucune volumétrie physique ni météo temps réel.
La disponibilité des services marins distants reste indépendante de ce changement.

## Deux passes de revue, même agent

**Revue 1 — architecture, code et premiers rendus.** Vérification de la fenêtre,
des courbes, du cycle de vie du codec/image, de l’absence de ticker, du repaint
sans reconstruction générale, des gestes et de la conservation des sources
marines. Les textures initiales trop filamenteuses ont été densifiées à partir
de trois découpes NASA distinctes. Un saut potentiel du cap 359°/0° a été corrigé
avec un décalage périodique ; test de pixels 0° = 360°. Analyse et 531 tests passent.
Les premières captures réelles et leurs planches confirment les bancs et les
ouvertures, ainsi que la dissipation.

**Revue 2 — reprise des exigences et des preuves réelles.** Examen des 16 captures,
des séquences avant/arrière, de l’arrêt et de la carte marine. Le contrôle tactile
a révélé que la première injection lente ne zoomait pas : elle n’a pas été
comptée comme réussite. Après correction du scénario d’injection, les valeurs
natives et la vidéo prouvent le passage Z4 → Z6,259 et le retour. Le signal Android
de réduction des animations a été testé réellement, puis les réglages restaurés.
Les 429 ont été distingués du rendu du composant et les détails marins vérifiés
sur le backend local. Les timings et leurs limites sont conservés ci-dessus,
sans les présenter comme une preuve de FPS constants. Aucun autre défaut visuel
bloquant identifié dans les scènes examinées. Ces passes ne sont pas indépendantes.

## État Git final

Branche `feature/marine-bathymetry`, HEAD `d78f2563`, index inchangé.
Aucun commit, push, PR ou changement de branche. Modifications limitées au mobile,
à ses textures, outil et tests, et à ce rapport. La photo et les archives SHOM
non suivies préexistantes sont conservées. Les empreintes des fichiers du globe
et des couches métier existantes passent toutes.
Listing exact : `test-results/cloud-passage-2026-10-18/git-final.txt`.
