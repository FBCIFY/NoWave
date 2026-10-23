# Fluidité cartographique — 23 octobre 2026

Les quatre changements applicatifs réduisent les lectures caméra redondantes, les encodages GeoJSON inchangés, les comparaisons de collisions dans les grands ensembles de ports et les reconstructions Flutter dues au cap. **901 tests Flutter réussissent.** Les gains chiffrés ci-dessous concernent l'hôte Linux/WSL avec Mapbox simulé. Le téléphone n'est plus connecté lors de la reprise : la comparaison finale sur appareil et la recette visuelle restent à faire. Publication en **draft PR**, sans fusion ni déploiement.

## A. Référence Git

- Dépôt `FBCIFY/NoWave`, branche existante `perf/map-smoothness-20261022`, worktree `/home/palms/NoWave-map-performance`.
- Référence historique initiale de `dev` et de la branche distante : `747759b0db86b58d58372a8a1c71cfabedba7c48`.
- Les deux passes d'audit et l'instrumentation ont précédé l'interruption. La reprise retrouve `cdce64bcaed11d269db2a15d48d17dcff4f8d133`, avec le lot caméra non committé, conservé puis complété.
- La PR #125 avait été intégrée localement par `40feb7ff`, avant les mesures, pour conserver ses corrections côtières. Depuis, sa fusion par un autre intervenant donne `origin/dev=dd46548be7707f3bfe4aac10a42a6b1770b57b8d`.
- `git diff 40feb7ff origin/dev` est vide : les arbres de référence sont identiques. L'intégration de ce nouveau `origin/dev` sur la seule branche de performance est sans changement de contenu, par `d26366168324a02434bd5bfd10a87c0261426ce7`.
- SHA final applicatif mesuré : `d26366168324a02434bd5bfd10a87c0261426ce7`. Les commits suivants ajoutent le benchmark de décodage, les preuves et ce rapport ; le HEAD publié complet figure dans la PR et dans `git log`.
- Le diff final contre `origin/dev` porte uniquement sur le mobile, ses outils/tests et le présent rapport. Aucun changement backend, verrou de dépendances, palette, source nautique, workflow, secret ou configuration de production.

Le worktree principal reste sur `fix/NW-220-coastal-raster-artifacts`. Ses dossiers utilisateur `docs/design/` et `mobile/codex_photo/` ne sont ni ajoutés ni modifiés par cette mission.

## B. Double audit

La première passe a suivi les callbacks caméra, cap, installation du style, données, réseau et rendu jusqu'aux sources Mapbox. La contre-analyse a relu les protections existantes, les tests, les rapports antérieurs et le SDK **2.30.1 installé**. La reprise complète cette contre-analyse avec les résultats de concurrence et le diff final. Les passes sont successives, effectuées par le même intervenant ; elles ne constituent pas une revue humaine indépendante par un second auteur.

| Priorité | Fichiers / composants examinés | Constat et preuve | Risque | Décision |
| --- | --- | --- | --- | --- |
| Existant | `marine_viewport.dart`, `marine_tiles.dart` | Fenêtre 200 ms, premier appel immédiat, deux clients actifs, neuf cellules par famille, caches 64 snapshots / 12 Mio, conservation des données et cellules de contours Z12 | Perte de données si simplification globale | Conserver ces mécanismes |
| P1 | `map_screen.dart`, `MarineViewport.schedule/synchronize` | L'événement fournit déjà `cameraState`, mais chaque synchronisation relisait la caméra native ; vérifié dans le SDK et par le faux Mapbox compteur | État ancien, changements pendant un await, reprise | Réutiliser l'événement avec génération, vérifier aussi après la lecture des bounds |
| P1 | `MarineViewport._render/features/_fetch` | Le JSON complet était encodé avant comparaison ; la référence chaude traite 20 000 coordonnées et réencode les collections | Signature ID/hash insuffisante, géométrie périmée | Réutiliser l'encodage seulement si la séquence et les objets/propriétés sont exactement équivalents |
| P1 | `HarbourSelection.select`, `harbour_layer.dart` | Comparaison quadratique avec les ports déjà retenus ; 1 000 candidats espacés mesurés | Frontières, priorités, symboles hors écran | Grille spatiale pour au moins 128 candidats ; prédicat flottant et ordre originaux conservés |
| P2 | `MapScreen._setCompassTurnsForHeading`, `location_marker.dart` | 120 caps variables donnent 120 reconstructions de l'écran et du widget Mapbox dans chaque essai initial ; NW-201 ne prouve pas de manque de FPS sur iPhone | Cap, nord, flèche, cycle de vie | Notifier local à la flèche ; ne pas confondre reconstruction Flutter et création d'une vue native |
| P2 | `_fetch`, API `map_tiles.py`, cache/service marin | Décodage synchrone mesurable ; expérience host séparée avec `Isolate.run` | Transfert, spawn, résultats obsolètes, absence de profil final sur téléphone | Garder le décodage actuel ; conserver l'outil de comparaison |
| P2 | `report_tiles.dart`, `report_layer_controller.dart`, réseau marin | Sources vectorielles déjà utilisées ; annulation ciblée par fermeture d'un client ; backoff et reprise déjà présents | Perte d'annulation et surcharge | Garder clients séparés, concurrence et quotas ; renforcer le test 429 |
| P2 | `globe_rotation_controller.dart`, `globe_pitch_controller.dart`, `heading_camera.dart`, `map_motion.dart`, caméras de sélection/notification/GPS | Rotation 2°/s, cadence minimale 33 ms, une commande en vol ; gestes prioritaires et contrôleurs de pitch/cap déjà protégés | Caméras contradictoires | Aucune modification de leur arbitrage ; suite de navigation complète |
| P2 | `map_config.dart`, `globe_style.dart`, `globe_presentation.dart`, `globe_stars.dart`, ponts Android/iOS | Étoiles fixes avec catalogue stable et `RepaintBoundary`, fog natif, SDK transparent avec `textureView:true` | Rendu différent ou perte des étoiles | Configuration native de production conservée ; variante TLHC uniquement sous diagnostic explicite |
| P3 | `buoy_layer.dart`, `fixed_aid_layer.dart`, `hydrography_layer.dart`, `port_layer.dart`, `marine_map_controller.dart`, `marine_zoom.dart`, backend marin | Chaque famille a des garanties de précision, de persistance et d'opacité ; MVT déjà utilisé pour infrastructures/signalements | Quantification et fragments variables selon zoom | Pas de migration générale ; analyse par famille en section H |

Rapports relus : `map-fluidity-2026-10-20.md`, `NW-201.md`, `nw-219-globe-2026-10-21.md`, `NW-220-validation-finale.md`, `NW-220-color-correction-2026-10-22.md`, et correction côtière de #125. Les performances anciennes et leurs limites ne sont pas réinterprétées comme une preuve de gain de cette branche.

## C. Corrections et preuves de non-régression

### Caméra — `83ab6cc2`

`MapScreen._handleMapCameraChange()` transmet l'état reçu à `MarineViewport`. Le dernier état en attente remplace les événements intermédiaires. Une lecture native commencée avant un nouvel événement ne peut pas le rétablir ; une réponse de bounds ancienne ne peut pas lancer les téléchargements de l'ancienne région. Les `padding` caméra sont transmis aussi.

Les appels directs sans état, l'installation du style et la reprise continuent à lire la caméra native. La cadence de 200 ms et le premier chargement immédiat restent identiques. Les cellules restent pilotées par centre/zoom ; bearing et pitch ne provoquent pas de nouveau téléchargement de cellules en cache, mais les bounds et les collisions sont recalculés. Le faible coût résiduel de construction des neuf cellules n'a pas justifié un second cache de plan de requêtes.

Six cas dédiés vérifient réutilisation, lecture native retardée, bounds retardés, événements coalescés, pause pendant lecture caméra/bounds et reprise. Les tests existants vérifient resize, style, régions éloignées, annulations et dernière position utile.

### Collisions — `f119c626`, complétées par `a0cb9e23`

Le tri, les identifiants, les priorités, l'ordre de rétention et le test strict `abs(dx)<spacing && abs(dy)<spacing` restent identiques. Seule la recherche des voisins utilise les neuf cases adjacentes d'une grille de pas `24*1.12+6`. Les coordonnées projetées ne sont ni arrondies ni déplacées : `floor` sert uniquement à indexer les cases.

Les petits ensembles gardent la liste initiale : les premiers essais ont montré que neuf recherches de cases apportaient un surcoût inutile pour 100 ports. Un oracle conserve l'algorithme quadratique de la référence. Les résultats complets et les états de priorité sont comparés pour 10, 100, 127, 128 et 1 000 ports, sur 30 transformations successives : rotation, compression verticale simulant le pitch, entrées/sorties, changements de zoom et perte de priorité hors écran. Le cas des frontières négatives, des superpositions et de l'espacement exact force aussi le chemin grille avec des candidats hors écran supplémentaires.

### GeoJSON — `fa5370fd`, complété par `a0cb9e23`

Un dernier encodage est conservé par source, soit cinq collections au maximum. La comparaison parcourt les objets dans leur ordre, sans empreinte probabiliste ni simple liste d'ID. Les snapshots sont traités comme des objets en lecture seule, conformément à leurs usages internes. Les wrappers de propriétés portuaires sont comparés sur toutes leurs clés, dont `selection_order`. Une nouvelle géométrie avec le même ID invalide la réutilisation.

La fusion et la conservation des points/courbes ne changent pas. La liste supplémentaire partage les objets des snapshots ; elle peut retenir temporairement des objets sortis du cache, jusqu'au remplacement de la collection, et est libérée à `dispose`. Le nombre de collections est borné ; l'impact mémoire réel reste à mesurer sur appareil.

Le cache d'encodage est distinct du cache de publication. Un style rechargé republie les cinq sources, même si les JSON sont réutilisés. Une source manquante ou une publication en échec reste retentable. Le sérialiseur natif et les révisions existantes empêchent un ancien rendu de finir après un rendu plus récent. Six tests dédiés couvrent également visibilité portuaire, nouveau `selection_order`, remplacement de géométrie, installation tardive d'une source et reload pendant publication.

### Boussole — `e722e24d`

Le calcul du plus court angle et le seuil de 1° ne changent pas. `_compassTurns` devient un `ValueNotifier<double>` écouté seulement autour de `_NavigationGlyph`, à côté du notifier de rotation caméra existant. Il est détruit avec l'écran. Le cap de la caméra, le puck, les libellés des modes et leurs transitions gardent leurs chemins existants.

Le benchmark vérifie maintenant zéro reconstruction de l'écran et du widget Mapbox pendant les changements de cap, **tout en exigeant la reconstruction de la flèche**. Ce changement d'assertion est le comportement attendu de l'optimisation, pas la suppression d'une assertion fonctionnelle de navigation. Les tests de cap/nord, continuité angulaire, suivi, gestes et réduction des animations restent inchangés et passent.

### Instrumentation — `cdce64bc`

`MapPerformance` est activé uniquement par `NOWAVE_MAP_PROFILE=true` hors release. Il collecte des distributions bornées à 12 000 observations par métrique : UI/raster Flutter, durée des événements de rendu Mapbox, lectures caméra/bounds, fusion, projection, sélection, encodage et publication. Aucun journal par frame. La création de cartes natives est comptée séparément des reconstructions Flutter.

Les diagnostics VM marins restent accessibles en debug et deviennent accessibles en profile avec ce flag explicite. Ils restent désactivés en release. `map_performance_profile.dart` sert des données synthétiques sur loopback, sans session utilisateur ni API de production ; sa tuile transparente ne reproduit pas la charge GPU d'une véritable bathymétrie. `map_performance_validation.py` automatise trois répétitions de quatre scénarios, distingue Flutter/Mapbox/mémoire et attend le chargement avant les mesures chaudes. Cet outil prépare la recette restante, il ne prouve pas son exécution finale.

## D. Performances mesurées

### Hôte — comparaison reproductible

Référence instrumentée `cdce64bc`, après `d2636616`. Flutter 3.47.6 / Dart 3.13.5, Linux x64 / WSL, tests debug, Mapbox simulé, mêmes données et mêmes commandes. Trois exécutions séparées par variante ; chaque mesure de données contient elle-même trois lots. Les deux variantes sont exécutées successivement, pas simultanément. Aucune comparaison debug/profile.

Preuves compactes : [mesures des six exécutions](artifacts/map-smoothness-2026-10-23/host-comparison.json), [décodage et transfert isolate](artifacts/map-smoothness-2026-10-23/decode-host.jsonl). Les logs locaux complets sont dans `test-results/map-performance/`, ignoré par Git. Les deux benchmarks restent versionnés pour reproduction.

| Mesure host | Avant | Après | Évolution observée |
| --- | ---: | ---: | ---: |
| Sélection 10 ports, médiane de neuf lots | 51 µs | 48 µs | -6 %, écart petit et bruité |
| Sélection 100 ports, médiane de neuf lots | 220 µs | 217 µs | -1 %, pas de gain significatif revendiqué |
| Sélection 1 000 ports, médiane de neuf lots | 1 876 µs | 728 µs | -61 %, environ 2,58 fois plus rapide |
| Sync chaude, 1 000 courbes / 20 000 coordonnées, médiane de neuf lots | 6 149 µs | 805 µs | -87 %, environ 7,64 fois plus rapide |
| Reconstructions `MapScreen`, 120 caps, chaque répétition | 120 | 0 | Écran isolé |
| Reconstructions `MapWidget`, 120 caps, chaque répétition | 120 | 0 | Widget isolé ; pas un compteur de cartes natives |
| Flèche reconstruite, après, chaque répétition | Non comptée | 120 | Les mises à jour restent visibles dans le test |
| Médiane du temps complet `pump`, médiane des trois essais | 2 906 µs | 377 µs | -87 % ; temps du test, pas durée UI native |
| P95 du temps complet `pump`, médiane des trois essais | 5 216 µs | 619 µs | -88 % ; même limite |
| Requêtes du scénario de données, chaque répétition | 45 | 45 | Aucune donnée supprimée ; aucune requête chaude supplémentaire |
| Lectures caméra dans ce benchmark à appels **directs** | 31 | 31 | Chemin de secours conservé |

Le test caméra avec état événementiel observe zéro lecture native supplémentaire ; le test direct observe toujours sa lecture. Le test d'encodage vérifie zéro nouvel encodage pendant cinq synchronisations chaudes et après reload du style, avec republication effective. Les tableaux ci-dessus ne remplacent pas un profilage Android/iOS.

### Décodage — alternative évaluée, non livrée

`dart run mobile/tool/map_json_benchmark.dart` compare le même décodage/conversion et valide les résultats complets. Trois observations après échauffement, hôte Dart VM :

| Volume | Décodage synchrone, médiane | Isolate, durée totale médiane |
| --- | ---: | ---: |
| 53 803 octets / 100 courbes | 669 µs | 1 066 µs |
| 538 084 octets / 1 000 courbes | 4 228 µs | 8 440 µs |
| 2 700 484 octets / 5 000 courbes | 21 863 µs | 43 860 µs |

L'isolate libère potentiellement le thread UI pendant le décodage, mais sa durée totale augmente ici. Ces nombres seuls ne tranchent pas son intérêt sur téléphone. Pas de seuil ni d'isolate applicatif ajouté sans comparaison des frames et du transfert sur appareil. Le risque de blocage synchrone pour les grosses réponses reste identifié.

### Flutter, Mapbox et système sur appareil

| Métrique physique | Avant | Après | Statut |
| --- | ---: | ---: | --- |
| Fréquence réelle et budget d'image | — | — | À relever sur l'appareil connecté |
| Frames Flutter hors budget | — | — | Pas de comparaison finale disponible |
| P95 UI Flutter | — | — | Idem |
| P95 raster Flutter | — | — | Idem |
| Durée de rendu Mapbox natif | — | — | Idem ; distincte des FPS et des timings Flutter |
| Décodage / encodage / publication sur téléphone | — | — | Instrumentation disponible, pas de paire exploitable conservée |
| Appels caméra et requêtes sur téléphone | — | — | Tests simulés seuls pour cette révision finale |
| Mémoire Dart / native / GPU, batterie et température | — | — | Non mesurées sur la révision finale |

La session précédente avait commencé des essais Android, mais aucune comparaison finale avant/après exploitable n'est conservée dans ces preuves. Aucun chiffre de cette session n'est repris comme résultat de la branche finale. Lors de la reprise, `adb devices -l` est vide et `flutter devices` ne retourne que Linux. Aucun appareil iOS n'est disponible.

## E. Validation NW-220 et scénarios

| Garantie | Contrôle effectué | Portée / preuve |
| --- | --- | --- |
| Bathymétrie Z5, palette, côtes, cache `marine-visual-7`, composition | Aucun diff de palette/raster/backend ; tests du contrôleur marin | Conformité logicielle ; nouvelle vérification visuelle native manquante |
| Ports preload Z6, visibilité Z8, enrichissement Z10 | Tests du viewport et couches + oracle de sélection | Réussi, jusqu'à 1 000 candidats |
| Marques preload Z10, opacité nulle à Z10, fondu linéaire à Z12 | Tests existants bouées/aides fixes/zoom | Réussi ; mêmes couches, classes IALA et géométries |
| Courbes preload Z12, affichage Z13, grille Z12 jusqu'à Z18 | Tests existants de persistance et géométrie | Réussi ; aucune modification de propriété ou quantification |
| Sondes et overzoom | Tests hydrographie / viewport | Réussi ; source et résolution inchangées |
| IDs et positions géographiques | Tests existants de rétention + remplacement de géométrie de même ID | Réussi ; aucun déplacement artificiel |
| Resize / iOS sans `getSize` natif | Test existant viewport iOS | Réussi avec viewport logique Flutter |
| Style rechargé | Republication complète et reload pendant publication | Réussi, publication sérialisée |
| Réseau dégradé | 429, 503, timeout, réponses partielles, récupération et annulations | Réussi ; clients distincts et backoff conservés |
| Cache/concurrence | Tests bornes, réponse utile retardée, changement de région, pause/reprise | Réussi ; budgets inchangés |

Aucune recette physique ni vérification visuelle nouvelle n'est revendiquée pour les vingt scénarios suivants. « Automatique » signifie tests avec SDK simulé ou contrôleurs isolés, pas gestes réalisés sur appareil.

| N° | Scénario | Automatique | Appareil / visuel final |
| --- | --- | --- | --- |
| 1 | Globe Z0–Z0.7 | Contrôleur rotation / limites | Non vérifié |
| 2 | Globe Z0–Z4.5 | Rotation / pitch / présentation | Non vérifié |
| 3 | Rotation automatique | Une commande en vol, vitesse et cadence | Non vérifié |
| 4 | Interruption au toucher | Contrôleur et widget globe | Non vérifié |
| 5 | Zoom continu Z0 → Z6 | Seuils / pitch / gestes simulés ; pas parcours tactile continu | Non vérifié |
| 6 | Déplacement maritime rapide | Caméra retardée, cellules obsolètes, régions éloignées | Non vérifié |
| 7 | Bathymétrie à Z5 | Contrôleur marin / seuil | Non vérifié |
| 8 | Ports Z6–Z10 | Viewport, couches et oracle | Non vérifié |
| 9 | Marques Z10–Z12 | Fondu / séparation preload-placement | Non vérifié |
| 10 | Sondes Z13 | Couche hydrographique et viewport | Non vérifié |
| 11 | Courbes Z12–Z18 | Persistance et retour de zoom | Non vérifié |
| 12 | Rotation/pitch près d'un port dense | Positions projetées simulées et oracle ; pas projection SDK physique | Non vérifié |
| 13 | Retour sur zone chaude | Benchmark et caches / requêtes | Non vérifié |
| 14 | Reload style | Géométries et cinq sources republiées | Non vérifié |
| 15 | Rupture/rétablissement réseau | 429/503/timeout/annulation/reprise | Non vérifié |
| 16 | Réponses partielles | Conservation / enrichissement des courbes et points | Non vérifié |
| 17 | Recentrage GPS | Navigation, caméra, focus et suivi simulés | Non vérifié |
| 18 | Rotation du téléphone | Cap et continuité angulaire injectés ; resize simulé | Non vérifié |
| 19 | Ouverture/fermeture signalement | Focus, fiches, caméra et création simulés | Non vérifié |
| 20 | Arrière-plan/reprise | Lifecycle, annulations et reconnexion simulés | Non vérifié |

## F. Vérifications et reproduction

Commandes exécutées depuis `mobile`, Flutter 3.47.6 / Dart 3.13.5 :

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

Résultats : **249 fichiers conformes**, **aucun problème d'analyse**, **901 tests réussis**, **0 échec**, fin de suite en 43 s. Dix-huit nouveaux cas de régression ciblés, plus le nouveau benchmark de données ; le test réseau existant est renforcé sans retirer les assertions 503/timeout. Les tests widget affichent les messages d'API Mapbox non implémentées par leurs fakes ; cela ne constitue pas une validation SDK native et ne produit aucun échec de test.

Lots intermédiaires : caméra et viewport 22 tests puis six cas caméra complétés ; sélection/couches/viewport/benchmark 25 tests, puis oracle renforcé aux deux côtés du seuil 128 ; encodage, viewport et caméra 25 tests puis six cas d'encodage complets ; orientation/caméra/globe/boussole 24 tests. Le résultat de référence pour chaque cas final est la suite complète de 901 tests.

À la racine : `git diff --check`, Ruff sur `mobile/tool/map_performance_validation.py`, compilation Python du même outil, formatage des deux outils Dart nouveaux : réussis. Les appels backend de production n'ont pas servi de test de charge. Aucun fichier backend n'est changé par rapport à `origin/dev` ; sa suite sera néanmoins exécutée par la CI de PR inchangée.

Pour reproduire les mesures host, utiliser un checkout détaché `cdce64bc` et la branche finale, puis dans chaque `mobile` :

```sh
flutter pub get --offline
# Trois exécutions distinctes, avec trois lots internes pour les données.
flutter test --no-pub test/performance/map_data_benchmark_test.dart \
  test/performance/compass_rebuild_benchmark_test.dart --reporter expanded
# Expérience de décodage disponible sur la branche finale uniquement :
dart run tool/map_json_benchmark.dart
```

La référence conserve l'assertion de reconstruction attendue avant optimisation ; la branche finale exige l'isolation. Ni l'une ni l'autre ne simule une carte native recréée. Les petites différences d'hôte sont sensibles au JIT et à l'ordonnancement : les assertions fonctionnelles, pas les durées, décident du succès des tests.

Pour la recette physique restante, fournir le fichier privé existant sans l'afficher ni le modifier et adapter le device :

```sh
flutter run --profile --no-pub -t tool/map_performance_profile.dart \
  --dart-define-from-file=/home/palms/NoWave/mobile/.env.json \
  --dart-define=NOWAVE_MAP_PROFILE=true \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:18097 -d DEVICE
```

Le scénario synthétique sert à isoler les coûts. Effectuer également les vingt parcours dans `lib/main.dart` avec les vraies couches, dont raster côtier, symboles, réseau dégradé, GPS et notifications. Comparer la même zone/cache/réseau/durée au moins trois fois, avec refresh rate, batterie/température et mémoire documentés. Une variante native peut être essayée avec `NOWAVE_MAP_HOSTING=TLHC` et le même protocole ; le réglage de production reste VD.

## G. GitHub et état de livraison

Commits applicatifs : `83ab6cc2` (caméra), `f119c626` (grille), `fa5370fd` (encodage), `e722e24d` (boussole), `a0cb9e23` (contre-vérifications). Instrumentation : `cdce64bc`. Intégration de `dev` sans différence de contenu : `d2636616`.

La branche doit être publiée uniquement vers `perf/map-smoothness-20261022`, cible `dev`. La PR est en brouillon jusqu'aux comparaisons physiques et à la recette native. Le lien, le SHA publié et les résultats distants sont consignés dans la description de la PR et dans le compte rendu de livraison ; ils ne sont pas anticipés dans ce rapport préparé avant publication. Les résultats locaux ne sont pas présentés comme une CI verte.

Aucune fusion de cette PR, modification directe de `dev`, action Linear ou livraison en production n'est effectuée. La fusion préexistante de #125 constatée à la reprise ne provient pas de cette mission.

## H. Optimisations non retenues et suite nécessaire

| Proposition | Décision, bénéfice possible et risque | Preuve nécessaire avant changement |
| --- | --- | --- |
| Changer 200 ms ou augmenter les deux téléchargements | Pas de changement : mécanismes déjà présents ; risque de rafales, coût serveur et collisions moins stables | Latences et frames physiques à froid/chaud, test de charge isolé |
| Client HTTP partagé | Pas de changement : annulation ciblée conservée | Pool compatible annulation individuelle et gain de connexions mesuré |
| Décodage isolate systématique | Pas livré : durées totales host plus élevées, bénéfice UI physique inconnu | Mesures de transfert, pic mémoire et frames sur grosses réponses ; gestion des générations après await |
| Cache supplémentaire des plans de cellules / projections | Pas livré : plan court déjà couvert par cache de snapshots ; projections nécessaires au bearing/pitch/layout et nouveaux ports | Coût résiduel significatif sur appareil et invalidation prouvée |
| Baisser résolution, masquer couches ou supprimer halo/étoiles | Écarté : incompatible avec les garanties visuelles | Ne fait pas partie de cette mission |
| SurfaceView opaque / remplacement des gestes natifs | Écarté : le SDK 2.30.1 impose TextureView pour `isOpaque:false` ; gestes natifs déjà prioritaires | Alternative visuelle strictement équivalente et profils natifs |
| TLHC/HC en production | Non retenu sans comparaison ; VD conservé | Trois essais thermiquement comparables, overlay étoiles/halo et gestes validés Android ; recette séparée iOS |
| Réécriture de l'arbitrage des caméras | Non justifiée par une nouvelle panne ; contrôleurs protégés, tests verts | Trace montrant des commandes contradictoires dans un scénario reproductible |

### Formats par famille et migration native

| Famille | Format actuel dans le mobile / alternative serveur | Garanties à préserver et décision |
| --- | --- | --- |
| Signalements | MVT déjà natif | IDs, sélection, authentification, expiration et notifications ; ne pas réimplémenter |
| Infrastructures portuaires | MVT déjà natif (`PortLayer`) | Géométries de quais/digues, maxzoom, cache et ordre ; conserver |
| Fond bathymétrique | PNG natif | Couleurs validées, côtes, cache/version, grille, alpha ; conserver |
| Ports ponctuels | GeoJSON / MVT marin disponible | Priorité stable, collisions écran et enrichissement inter-zooms ; une migration ferait changer la sélection |
| Marques et aides fixes | GeoJSON partagé par couches natives / MVT marin disponible | IDs IALA, propriétés et zoom de fondu ; coordonnées quantifiées variables dans MVT, risque de déplacement |
| Courbes | GeoJSON Z12 fixe / fragments MVT disponibles | Propriété fixe de cellule, précision et rétention de géométrie ; migration incompatible sans preuve d'équivalence |
| Sondes | GeoJSON jusqu'à Z16 / MVT disponible | IDs/propriétés/profondeurs, résolution et réponses partielles ; évaluer séparément |
| Dangers sous-marins | GeoJSON / MVT disponible | Identités, positions retenues, seuils et ordre par rapport aux marques ; même besoin d'audit séparé |

Le GeoJSON est déjà rendu par Mapbox natif après publication ; la présente optimisation réduit le travail Dart qui prépare ces sources. Une migration structurelle exige de comparer les propriétés, IDs, géométries aux frontières et sur plusieurs zooms, la conservation NW-220, les requêtes/cache et les coûts CPU/GPU. Elle doit être isolée si ces garanties ne peuvent pas être démontrées dans le même changement.
