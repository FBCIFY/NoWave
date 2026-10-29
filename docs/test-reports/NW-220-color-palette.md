# NW-220 — Globe et bathymétrie : validation de la palette

## A. Git et périmètre

- Worktree : `/home/palms/NoWave-NW220-colors`.
- Branche : `feature/NW-220-satellite-bathymetry-colors`.
- Base initiale propre : `70b248bc225442305c7fb6515d02f3c0aac2c8cd`.
- Branche parente laissée sur cette même base ; `dev` sur `c96a4c89db57fbd74687ef51e9c9cadd24196643`.
- Commit prévu après validation : `style(map): align globe and bathymetry color palette`.
- Aucun push, PR, merge, rebase, changement Linear, déploiement ou changement VPS.
- Configuration privée réutilisée par lien ignoré, sans modification de son contenu. Backend de test propre à ce worktree, port 8005 ; aucune modification du backend de l'autre worktree.
- Le SHA final et l'état après commit sont fournis dans la réponse finale ; le présent rapport appartient au commit qu'il décrit.

## B. Référence effectivement consultée

Le fichier attendu dans `codex_photos` est absent du worktree. La recherche par nom a retrouvé et ouvert, en lecture seule :

`/home/palms/NoWave/mobile/codex_photo/Infographie cartographique marine française.png`.

L'image n'est ni copiée ni ajoutée au commit. Analyse visuelle : mer marine sombre, luminosité croissante vers les faibles profondeurs, turquoise contenu ; terres vert forêt, olive, ocre, sable, urbain gris beige et neige blanc cassé. Contraste terre/mer net, halo cyan, espace presque noir, frontières secondaires. Les textures photographiques, symboles et zooms illustratifs ne sont pas des spécifications à reproduire.

Palette marine retenue, du profond au peu profond : `#001731`, `#002D51`, `#00325A`, `#014A6B`, `#0E6985`, `#61AAA4`. Aucun seuil métrique n'est déduit de ces six couleurs.

## C. Double audit avant modification

### Première passe : producteurs et consommateurs

Lecture de `marine_map_controller`, `marine_zoom`, `hydrography_layer`, `marine_viewport`, `map_screen`, puis de leurs dépendances de rendu directes : `globe_style`, `globe_presentation`, rotation, nuages, lune, étoiles, palette et producteur EMODnet.

| Composant initial | Source / identifiant | Type, zoom, opacité et ordre |
|---|---|---|
| Fond terrestre | import `basemap`, Mapbox Standard | cartographie native, thème `faded`, éclairage `day`, tous zooms |
| Photographie | `nowave-satellite` / `nowave-earth-satellite` | raster Mapbox Satellite, MIDDLE, opaque jusqu'à Z4, fondu jusqu'à Z7 |
| Teinte océan globe | Streets v8 `water`, `nowave-earth-ocean` | fill MIDDLE, `#0A4E87`, opacité .28 à Z3 puis 0 à Z7 |
| Nuages globe | quatre sources image `nowave-clouds-*` | PNG NASA en MIDDLE, opacité 1 à Z1, .65 à Z3, 0 à Z5 |
| Nuages de passage | `CloudPassage` et son contrôleur | overlay Flutter dépendant de la caméra, atlas NASA distinct |
| Lune | `GlobeMoon` | overlay Flutter derrière la carte, PNG LRO, fondu aux petits zooms |
| Étoiles | `GlobeStars` | fond Flutter fixe, catalogue stable, atténuation Z0–Z6 |
| Atmosphère | `fog` de `GlobeStyle` | couleur cyan `#84D6F2`, halo bleu, interpolation native |
| Raster marin | `nowave-bathymetry-raster` | PNG backend, MIDDLE, min Z5, opacité 1, source max Z14 et overzoom |
| Courbes / sondes | sources GeoJSON NW-220 | données préchargées Z12, lignes et labels MIDDLE dès Z13 |
| Marques | sources GeoJSON NW-220 | TOP ; fondu linéaire Z10–Z12 ; placement et priorités dédiés |
| Frontières | Standard désactivées | ajout nécessaire de limites nationales discrètes sur données réelles |

La couleur marine provient déjà des pixels : `emodnet_bathymetry._NOWAVE_RAMP` et LUT 33³. Le fournisseur est `emodnet:mean_multicolour`, dont la rampe RGB observée encode l'ordre des profondeurs. Il ne fournit pas ici des mètres bruts ; on préserve cette information d'ordre sans prétendre décoder une profondeur métrique supplémentaire. Aucun calcul de distance au rivage.

### Deuxième passe : contraintes et compatibilité

Vérification des consommateurs d'assets avant retrait : les fichiers du dossier `assets/globe`, leurs deux générateurs et les composants nuages/lune ne servent qu'aux décorations supprimées. Les étoiles et le fog sont indépendants. Les cinq tests des composants nuages retirés disparaissent avec ces composants ; les tests de rotation, d'étoiles, de caméra et NW-220 restent exécutés.

Vérification de Mapbox Flutter installé 2.30.1 : les propriétés fill, line, slot et raster employées existent. `raster-color` existe également, mais une projection linéaire des canaux ne remplace pas l'inversion de la rampe EMODnet non monotone déjà réalisée côté backend. La solution minimale est donc de changer six couleurs dans le producteur, sans seconde couche raster.

Mapbox Standard conserve routes, bâti, libellés et usages des sols. Une source Terrain v2 ajoute les classes réelles `wood`, `scrub`, `grass`, `crop`, `snow` et les polygones de relief `shadow`/`highlight` ; sa généralisation est une information cartographique, pas une classification scientifique inventée. Streets v8 existant est réutilisé pour les frontières `admin_level=0`, hors limites maritimes, avec différenciation des limites disputées et filtre de worldview évitant les duplications.

Références techniques consultées : [Standard](https://docs.mapbox.com/map-styles/reference/standard/), [Terrain v2](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-v2/), [Streets v8](https://docs.mapbox.com/data/tilesets/reference/mapbox-streets-v8/). Les règles NW-220 de concurrence, préchargement, cache et rétention ont été relues ; aucun changement nécessaire.

## D. Implémentation et fichiers

- `globe_style.dart` : retrait du satellite, des quatre nuages et de leur source d'attribution devenue inutile ; ajout des remplissages terrestres et de deux couches frontières. Le style reste unique à tous les zooms. Le fichier temporaire passe à `nowave-globe-v2`, sans copie d'images.
- `marine_palette.dart` : mer de repli `#002D51`, forêt `#395B32`, broussailles `#627545`, herbe `#7C8950`, cultures `#A39F6B`, neige `#ECEDE5` ; sol de base `#C4AD80`, usages urbains `#B5B1A2`, industrie `#AAA99D`, bâtiments `#BDB8A9`. Pas de recolorisation des marques.
- Terrain BOTTOM, opacité de couverture 1 ; relief ocre/brun à .22 jusqu'à Z12 puis fondu linéaire vers 0 à Z16. Océan BOTTOM opaque à tous les zooms, sous le raster réel dès Z5. Routes, bâti et labels restent au-dessus.
- `emodnet_bathymetry.py` : seulement six valeurs RGB changées. LUT, interpolation, alpha, lissage prémultiplié, halo de 3 pixels, échantillonnage, masque côtier, retries et LRU de 512 résultats inchangés.
- `marine_map_controller.dart` : URL `v=marine-palette-3`, pour séparer les anciens pixels en cache ; aucun cache de production purgé. Contraste et saturation additionnels remis à zéro pour restituer les couleurs produites. Raster unique, MIDDLE, min Z5, opacité 1, fade 150 ms, resampling LINEAR, max source Z14 inchangés.
- `hydrography_layer.dart` : seules les couleurs des courbes (`#6F9FA8`), des chiffres (`#D8E7E9`) et de leur halo (`#123A50`) changent. Largeurs, opacités, placement, valeurs et seuils identiques.
- `map_screen.dart` : seuls branchements nuages/lune supprimés ; `globe_presentation.dart` : commentaire actualisé. Pas de changement des signalements, menus, GPS, rotation ou interactions.
- Retrait des composants dédiés `cloud_passage_controller.dart`, `cloud_passage.dart`, `globe_moon.dart`, de leurs assets, provenance/README spécifiques et générateurs `prepare_globe_assets.py`/`prepare_cloud_passage.py`. Retrait de leur entrée `pubspec.yaml`.
- Tests de style, source, erreurs et raster actualisés pour le contrat demandé. Le test de continuité balaie désormais toute la rampe source : plus de 128 couleurs, transitions de canal limitées à un niveau 8 bits, extrémités exactes ; les tests d'alpha, coutures, cache et ordre de luminosité sont conservés.

## E. Globe

Nuages géographiques, overlay de passage et lune supprimés du code et des ressources embarquées. Pas d'autre astre ajouté. Halo, liseré cyan, projection, caméra initiale, fond spatial et étoiles conservés à l'identique. Frontières `#F0F0F0`, opacité .18, largeur .6 px, sans halo ni doublure sombre ; limites disputées en tirets.

La rotation n'est pas modifiée. La base autorise en fait Z0–Z4.5 dans `GlobeRotationController`, incluant bien Z0–Z0.7 demandé ; cette refonte colorimétrique ne resserre pas cette plage existante.

## F. Double validation

### Première passe

Revue du diff et exécution des suites. Correction des assertions d'anciennes couleurs et d'une comparaison de listes imbriquées. Vérification visuelle sur LGN LX1, Android 15/API 35, application réelle `fr.blueway.app`, sans désinstallation, purge, faux signalement ou simulation GPS. Les déplacements concernent uniquement la caméra via l'extension debug existante.

Une première série a rencontré `ERR_CONNECTION_CLOSED` sur `mapbox-dem` de Standard et l'écran de réessai existant. Elle n'est pas validée : réessai réel, nouvelle série complète sans erreur marine. Aucun contournement de la gestion des erreurs.

### Deuxième passe

- `dart format --output=none --set-exit-if-changed lib test` : 210 fichiers, aucun changement.
- `flutter analyze --no-pub` : aucune anomalie.
- `flutter test --no-pub` : 714 tests réussis, dont non-régression NW-220 et présentation du globe.
- Backend Python 3.12.15, dépendances du lock `requirements-test.txt` : 975 tests réussis, 1 ignoré (archives locales SHOM XYZ absentes, hors MVP) ; tests Nginx/Compose inclus avec exécutables locaux isolés.
- Tests raster : 14 réussis ; Ruff ciblé : réussi.
- Huit reconstructions successives de LUT sous Python 3.12 : réussies.

L'environnement Python 3.14 préexistant a produit de façon intermittente un SIGSEGV et un TypeError pendant la construction de LUT, malgré une suite complète réussie. Désactiver le JIT ne résout pas systématiquement le problème : la cause n'est donc pas attribuée au JIT. Validation finale effectuée dans un venv 3.12 propre au worktree, conforme au Dockerfile, sans changement de dépendances du projet. Ce défaut de l'environnement 3.14 reste distinct de la cible 3.12 validée.

Les traces, captures et scripts ponctuels restent dans `test-results/colors/` ignoré. Les 14 demandes de capture couvrent Z0, .7, 1, 3, 5, 8, 10, 11, 11.9, 12, 12.99, 13, 14, 16 ; Toulon / La Seyne / Saint-Mandrier pour les vues côtières. Les captures avant correction de contraste des sondes sont complétées par celles du rendu final.

Comparaison visuelle : famille marine conforme, très faibles profondeurs turquoise modéré, terre/mer contrastées, végétation naturelle, côtes et détails routiers conservés. Le globe et les vues régionales ont une texture vectorielle plus généralisée que l'infographie, volontairement sans photo. La bathymétrie garde la résolution réelle EMODnet : cellules visibles à fort zoom et petites zones de repli près des limites de couverture, sans profondeur fabriquée. Les mêmes couleurs servent à tous les zooms ; le raster enrichit le fond à Z5 comme imposé. Les densités de sondes après rétention restent celles de NW-220.

## G. Performances

Un raster satellite et quatre images globe retirés, ainsi que deux overlays Flutter. Source Terrain v2 ajoutée pour deux couches réelles ; Streets réutilisé. Cinq couches de style décoratif final au lieu de six, deux sources explicites au lieu de sept. Aucun traitement Dart par frame ajouté. Les fades sont natifs ; le contrôleur de nuages par caméra disparaît.

Microbenchmark local Python 3.12 sur PNG RGBA 262×262, 25 colorisations avec LUT chaude : médiane ancienne 3.29 ms, nouvelle 3.53 ms ; première LUT + colorisation 284 ms / 274 ms. Échantillon synthétique, pas une mesure réseau ni un benchmark FPS. Le coût algorithmique est identique. Pas de nouvelle dépendance applicative ni service payant.

Mesures Android et cycles : voir les preuves finales ajoutées ci-dessous. Les chiffres proviennent d'un build debug ; ils ne constituent pas une promesse de performance release.

## H. Préservation NW-220

Seuils strictement inchangés : raster Z5, préchargement profondeur Z12, affichage Z13, marques 0 à Z10, .5 à Z11 et 1 à Z12. `marine_zoom.dart`, `marine_viewport.dart`, les providers, découpage et identités, caches GeoJSON, concurrence, quotas et configuration Nginx n'ont aucun diff.

Ports, aides fixes, bouées et dangers : aucune modification de source, symboles, taille, couleur, classification, placement ou interaction. Le fond plus sombre change naturellement leur contraste perçu, sans modifier ces couches. Les trois seules couleurs hydrographiques modifiées sont explicitement détaillées plus haut.

## Preuves finales sur l'APK compilé

- Build debug final réussi ; avertissements KGP/Java déjà présents, sans échec de compilation.
- SHA-256 APK : `3030a3fd8c5d52b7348024dfc057b88476b92b66c7e9a1ef9bdd3b5d817c56f9`.
- APK installé puis testé à nouveau, sans dépendre d'un hot reload. Archive APK contrôlée : aucun asset `globe`, `cloud-passage` ou `moon.png` restant.
- Captures finales : `test-results/colors/final-captures/`, une PNG et un relevé natif JSON par zoom demandé. Elles ont été comparées à la référence consultée.
- **Limite native préexistante** : une demande Z0 est ramenée à **Z0.652844973** sur l'écran 360×805 points de ce téléphone, comme déjà documenté dans `nw-219-globe-2026-10-21.md`. Le fichier `z0.png` représente ce minimum réel, pas un Z0 natif obtenu. Pas de modification des contraintes caméra pour contourner cette limite. Z0.7 est atteint exactement.
- Rotation après geste relâché : +10.4584° au minimum natif et +10.5586° à Z0.7 sur environ cinq secondes de mesure ; latitude, zoom, bearing et pitch constants. Preuve `rotation.json`.
- Aucun label/courbe de profondeur rendu avant Z13 ; rendu natif confirmé à Z13/14/16. Marques absentes à Z10, présentes pendant le fondu Z11/11.9 et à Z12. Les expressions linéaires restent inchangées et testées.
- Rechargement du style à Z13 : couches réinstallées, capture réelle et 36 résultats rendus, aucune erreur marine (`style-reload.json/png`). Aucun `Chargement Mapbox en échec`, exception Flutter non gérée ou erreur d'installation de couche dans le journal de cette exécution finale. Avertissements de réflexion Mapbox au démarrage connus de la base, sans impact observé.
- Trois cycles Z12 → 12.99 → 13 → 14 → 16 → 14 → 13 → 11 → 10 → 8 → 5, puis déplacements Marseille / Port-Cros / Toulon et quatre commandes rapprochées : 37 états détaillés et retour final, aucune erreur marine. Les 26 identités de courbes communes gardent exactement leur SHA-256 géométrique à chaque rencontre. Script et résultats : `test-results/colors/regressions*`.
- Cache observé : au plus 45 snapshots / 915 495 octets encodés ; aucune modification des plafonds 64 / 12 MiB ni de la concurrence 2.
- Heap Dart en fin des trois cycles : 123 942 400 → 113 300 656 → 113 593 600 octets. Pas de croissance monotone sur cette séquence.
- Mémoire Android debug après la série finale : PSS 661 667 Ko, RSS 772 100 Ko, swap PSS 36 028 Ko. Durant l'exécution longue précédente : PSS 815 898 Ko. Pas de conclusion de baisse mémoire vs référence ni de FPS release.
- Neuf fichiers protégés (zoom, viewport, symboles, rotation, pitch, étoiles, Nginx) comparés octet par octet à la base : identiques. Le diff hydrographique ne touche que les trois couleurs autorisées.

Le rendu est jugé satisfaisant pour cette refonte colorimétrique : océans sombres et progressifs, terres cartographiques, absence totale des décorations retirées, atmosphère et fonctionnalités NW-220 conservées. La résolution des données sources et le minimum de zoom natif explicités ci-dessus ne sont pas modifiés.

## Inventaire exact des fichiers du commit

- `backend/app/infrastructure/adapters/emodnet_bathymetry.py`
- `backend/tests/unit/test_emodnet_bathymetry.py`
- `docs/test-reports/NW-220-color-palette.md`
- `mobile/assets/globe/README.md`
- `mobile/assets/globe/cloud-passage-atlas.png`
- `mobile/assets/globe/cloud-passage-provenance.json`
- `mobile/assets/globe/moon.png`
- `mobile/assets/globe/ne.png`
- `mobile/assets/globe/nw.png`
- `mobile/assets/globe/provenance.json`
- `mobile/assets/globe/se.png`
- `mobile/assets/globe/sw.png`
- `mobile/lib/core/map/cloud_passage_controller.dart`
- `mobile/lib/core/map/globe_presentation.dart`
- `mobile/lib/core/map/globe_style.dart`
- `mobile/lib/core/map/marine/marine_map_controller.dart`
- `mobile/lib/core/map/marine/marine_palette.dart`
- `mobile/lib/features/map/data/hydrography_layer.dart`
- `mobile/lib/features/map/presentation/map_screen.dart`
- `mobile/lib/features/map/presentation/widgets/cloud_passage.dart`
- `mobile/lib/features/map/presentation/widgets/globe_moon.dart`
- `mobile/pubspec.yaml`
- `mobile/test/core/map/cloud_passage_controller_test.dart`
- `mobile/test/core/map/globe_style_test.dart`
- `mobile/test/core/map/marine/marine_map_controller_test.dart`
- `mobile/test/features/map/data/api_sources_test.dart`
- `mobile/test/features/map/presentation/buoy_source_error_test.dart`
- `mobile/test/features/map/presentation/widgets/cloud_passage_test.dart`
- `mobile/tool/prepare_cloud_passage.py`
- `mobile/tool/prepare_globe_assets.py`
