# NW-220 — rapport complet de pré-publication

> Archive de la première validation. Pour la reprise, les corrections et les
> preuves du code final, consulter [la validation finale](NW-220-validation-finale.md).
> Le fondu des marques Z10–Z12 a été confirmé par l'utilisateur après cette
> première phase ; les seuils, empreintes et réserves ci-dessous sont historiques.
> Les liens vers le code pointent désormais vers les fichiers versionnés. Les
> captures, journaux et JSON de `test-results/` restent des preuves locales non
> versionnées : leur nom est conservé, sans lien GitHub trompeur.

**21 octobre 2026 — Phase A terminée sans publication. Verdict : PARTIELLEMENT VALIDÉ.**

L'implémentation locale et les tests automatisés sont réalisés. La véritable
application NoWave a été ouverte et testée sur le téléphone physique. La
conservation des ports et de trois isobathes est démontrée par identités,
géométries, requêtes natives et captures. Deux limites empêchent de présenter
l'ensemble comme entièrement validé : des indisponibilités Open Waters sur
certaines tuiles détaillées de Marseille et l'absence d'exemplaire réel de
`buoy_isolated_danger` récupéré dans les zones essayées. La balise fixe de danger
isolé et les huit combinaisons cardinales fixe/flottante N/E/S/O sont vérifiées.

## A. Références et état local

- Ticket : [NW-220](https://linear.app/blueway/issue/NW-220/carte-marine-seuils-de-zoom-et-persistance-des-couches-z5z8z10z12z13), description intégrale et commentaires lus avant modification.
- Branche : `feature/NW-220-marine-zoom-persistence`, cible future `dev`.
- Worktree isolé : `/home/palms/NoWave-NW220`.
- SHA `origin/dev` de départ et HEAD actuel : `98711c18a8cf19aaf875bd740037e94f13790cbb`.
- `origin/dev` récupéré par `git fetch origin dev`, puis branche créée depuis cette référence. Aucune branche/PR NW-220 trouvée lors des recherches initiales.
- Le worktree d'origine `/home/palms/NoWave` et ses fichiers préexistants `docs/design/` et `mobile/codex_photo/` ont été conservés. Aucun travail n'a été fait directement sur `dev`.
- Modifications **non committées et non indexées** ; aucun push, aucune création de PR, fusion ou publication. Linear laissé **In Progress**.
- Aucun déploiement de production/VPS. Le serveur de recette est local.
- Empreinte SHA-256 des fichiers de code, tests et outils modifiés : `65414ca0c7897aa16d98d8d690d790718dd9bcf9a0f5644cb1b003fab0dc8801`. Détail dans code-manifest.json (`test-results/NW-220/code-manifest.json`, preuve locale non versionnée).
- APK finale compilée et installée, SHA-256 : `1fb60e9118a44280e90d727aefe2cb9bd2a24d660ea12957111a609381d43519`. Comparaison avec le fichier réellement installé : **identique = true**, preuve apk-proof.json (`test-results/NW-220/apk-proof.json`, preuve locale non versionnée).
- Le code testé n'a pas de nouveau SHA Git : il s'agit du SHA de base ci-dessus **plus le diff local**, identifié par le manifeste et l'APK.
- Résumé du diff hors présent rapport : environ **2210 lignes ajoutées, 520 supprimées** ; nouvel accès GeoJSON borné, contrôleur de viewport/cache/sélection, séparation lignes/étiquettes, seuils, tests et outils Android. Patch local complet : review.patch (`test-results/NW-220/review.patch`, preuve locale non versionnée).
- `.env.json` reste privé, ignoré et non modifié. Le worktree utilise le fichier existant sans le copier dans les fichiers de revue. Aucun littéral de jeton détecté dans les fichiers modifiés/nouveaux.

### Fichiers modifiés ou ajoutés (31)

- [backend/app/api/routes/map_tiles.py](../../backend/app/api/routes/map_tiles.py)
- [backend/app/application/services/marine_tiles.py](../../backend/app/application/services/marine_tiles.py)
- [backend/app/infrastructure/marine/hydro_normalization.py](../../backend/app/infrastructure/marine/hydro_normalization.py)
- [backend/app/infrastructure/marine/hydro_providers.py](../../backend/app/infrastructure/marine/hydro_providers.py)
- [backend/app/infrastructure/marine/providers.py](../../backend/app/infrastructure/marine/providers.py)
- [backend/app/infrastructure/marine/viewport_encoding.py](../../backend/app/infrastructure/marine/viewport_encoding.py)
- [backend/tests/unit/test_marine_viewport.py](../../backend/tests/unit/test_marine_viewport.py)
- [backend/tests/unit/test_noaa_soundings.py](../../backend/tests/unit/test_noaa_soundings.py)
- [docs/architecture/marine-zoom-persistence.md](../../docs/architecture/marine-zoom-persistence.md)
- [docs/test-reports/NW-220-prepublication.md](../../docs/test-reports/NW-220-prepublication.md)
- [mobile/README.md](../../mobile/README.md)
- [mobile/lib/core/map/marine/marine_map_controller.dart](../../mobile/lib/core/map/marine/marine_map_controller.dart)
- [mobile/lib/core/map/marine/marine_zoom.dart](../../mobile/lib/core/map/marine/marine_zoom.dart)
- [mobile/lib/features/map/data/buoy_layer.dart](../../mobile/lib/features/map/data/buoy_layer.dart)
- [mobile/lib/features/map/data/fixed_aid_layer.dart](../../mobile/lib/features/map/data/fixed_aid_layer.dart)
- [mobile/lib/features/map/data/harbour_layer.dart](../../mobile/lib/features/map/data/harbour_layer.dart)
- [mobile/lib/features/map/data/hydrography_layer.dart](../../mobile/lib/features/map/data/hydrography_layer.dart)
- [mobile/lib/features/map/data/marine_debug.dart](../../mobile/lib/features/map/data/marine_debug.dart)
- [mobile/lib/features/map/data/marine_viewport.dart](../../mobile/lib/features/map/data/marine_viewport.dart)
- [mobile/lib/features/map/presentation/map_screen.dart](../../mobile/lib/features/map/presentation/map_screen.dart)
- [mobile/test/core/map/marine/marine_map_controller_test.dart](../../mobile/test/core/map/marine/marine_map_controller_test.dart)
- [mobile/test/features/map/data/api_sources_test.dart](../../mobile/test/features/map/data/api_sources_test.dart)
- [mobile/test/features/map/data/buoy_layer_test.dart](../../mobile/test/features/map/data/buoy_layer_test.dart)
- [mobile/test/features/map/data/fixed_aid_layer_test.dart](../../mobile/test/features/map/data/fixed_aid_layer_test.dart)
- [mobile/test/features/map/data/harbour_layer_test.dart](../../mobile/test/features/map/data/harbour_layer_test.dart)
- [mobile/test/features/map/data/hydrography_layer_test.dart](../../mobile/test/features/map/data/hydrography_layer_test.dart)
- [mobile/test/features/map/data/marine_viewport_test.dart](../../mobile/test/features/map/data/marine_viewport_test.dart)
- [mobile/tool/nw220_device_validation.py](../../mobile/tool/nw220_device_validation.py)
- [mobile/tool/nw220_extra_validation.py](../../mobile/tool/nw220_extra_validation.py)
- [mobile/tool/nw220_final_validation.py](../../mobile/tool/nw220_final_validation.py)
- [mobile/tool/nw220_vm.py](../../mobile/tool/nw220_vm.py)

## B. Fonctionnalités réalisées

| Fonction | Modification et résultat | Vérification | Limite |
|---|---|---|---|
| Ports Open Waters Z6/Z8/Z10 | Source Open Waters exclusive ; vrais téléchargements anticipés ; source de rendu vide avant Z8 ; sélection écran stable ; nouveaux candidats à Z10 | Agrégation réelle des 16 enfants Z8, traces Android Z6, matrice et séries ports | Couverture préparée bornée à neuf cellules ; indisponibilités amont détaillées en F |
| Conservation des icônes portuaires | Identité publiée conservée ; coordonnées du premier point récupéré ; priorité aux représentants déjà retenus ; reconstruction après style reload | Tous les ports initialement retenus encore dans le champ restent rendus sur le parcours contrôlé ; Saint-Mandrier Z8–Z18 | Rotation/inclinaison forçant une collision : le représentant le plus ancien gagne, autres objets consultables |
| Marques Z10/Z12 | Préparation à Z10 avec données de résolution Z12 ; toutes les couches disponibles à minZoom 12, opacité nominale 1 ; aucune couche transparente de préchargement | Réponses non vides avant affichage ; aucune marque à Z11,99 ; familles présentes à Z12 | Récupération effective limitée aux données et budgets des sources |
| Cardinales et dangers isolés | Couches de sécurité séparées avec overlap autorisé, selon type normalisé ; aucune exclusion des cardinales non qualifiées ; sécurité au-dessus des marques ordinaires | Huit combinaisons cardinales fixe/flottante N/E/S/O à Z12 et Z16 ; dangers isolés fixes et collisions réelles | Pas de bouée de danger isolé réelle trouvée ; contrat vérifié en tests, preuve Android de cette sous-famille manquante |
| Raster Z5 | minZoom 5 et opacité 1 ; ancien fondu retiré ; position MIDDLE au-dessus du décor satellite/océan qui l'atténuait | Captures Z4,99/Z5 examinées ; continuité aux zooms supérieurs ; crédits ouverts sur téléphone | Dépend de la couverture et disponibilité du raster fournisseur |
| Profondeurs Z12/Z13 | Préchargement GeoJSON Z12, couches lignes/annotations/sondes minZoom 13 ; données NOAA et EMODnet conservées ; sondes natives jusqu'à Z16 | Non vide à Z12, aucun rendu à Z12,99, rendu à Z13 ; requêtes réelles non vides de sondes Z16 après correction | Aucune profondeur ajoutée en absence de donnée ; observations et cellules modélisées restent distinctes dans leurs propriétés |
| Conservation stricte des courbes | Fragments WGS84 sur grille Z12 fixe, bords à propriétaire unique, identité source préservée ; aucun arrêt Z15 ; lignes indépendantes des annotations ; rafraîchissement par ajout d'identités | Trois courbes EMODnet réelles 50/100/200 m suivies Z13/14/15/16/18 ; empreinte géométrique unique par courbe ; pan, rotation et style reload | Conservation des données réellement récupérées dans le champ, avec budgets bornés ; aucune précision portuaire attribuée aux courbes généralisées |

Les courbes ont leurs opacités graphiques nominales .72/.48 ; leurs étiquettes
peuvent être supprimées par placement sans commander l'opacité des lignes.
Les seuils backend de récupération restent compatibles Z12 : ils n'ont pas tous
été relevés à Z13. Le nouveau format partage les fournisseurs, normalisations,
licences, caches HTTP et limites existants. Les routes MVT sont conservées.
Aucun fournisseur WPI/NGA ou classement de « port majeur » n'est introduit.

L'appui long liste les véritables ports et marques proches, y compris les objets
non dessinés. Il ne remplace pas les taps des signalements. Les PNG, règles IALA
A/B, GPS, boussole, projection, comptes, Firebase et signalements gardent leurs
contrats. Les tests de navigation des alertes et des reports font partie de la
suite Flutter. Aucun compte ou faux signalement n'a été créé pour la recette.

Contrat technique détaillé : [marine-zoom-persistence.md](../../docs/architecture/marine-zoom-persistence.md).
**Les courbes EMODnet généralisées conservées ne sont pas des levés de précision
portuaire ni une carte officielle de navigation.**

## C. Validation automatisée et deux passes

### Environnement réellement utilisé

- Flutter **3.47.6**, Dart **3.13.5**, `mapbox_maps_flutter` résolu **2.30.1**.
- Python de l'environnement projet : **3.14.4** (`/home/palms/NoWave/.venv`).
- `flutter doctor -v`, `flutter devices`, `adb devices -l` exécutés. Doctor conserve notamment des avertissements de licences Android et de multiples binaires ADB ; compilation et installation Android physiques réussissent.
- Docker/Compose : les deux premiers contrôles Compose échouaient car le lanceur Windows Docker n'était pas utilisable dans WSL. Les **vrais binaires Ubuntu** ont ensuite été téléchargés et extraits dans `/tmp/nw220-docker`, sans démarrer de moteur Docker ni modifier l'installation du poste. Les tests ont réellement exécuté Compose 2.40.3 et les contrôles concernés passent.

| Commande | Résultat final | Journal |
|---|---|---|
| `flutter pub get` | Réussi ; versions verrouillées conservées | pub-get.log (`test-results/NW-220/pub-get.log`, preuve locale non versionnée) |
| `dart format --output=none --set-exit-if-changed lib test` | **215 fichiers, 0 changement** | format-final.log (`test-results/NW-220/format-final.log`, preuve locale non versionnée) |
| `flutter analyze --no-pub` | **Aucun problème** | analyze-final.log (`test-results/NW-220/analyze-final.log`, preuve locale non versionnée) |
| `flutter test --no-pub` | **718 tests réussis** | flutter-tests-final.log (`test-results/NW-220/flutter-tests-final.log`, preuve locale non versionnée) |
| `ruff check .` | **Tous contrôles réussis** | Exécuté sur l'ensemble du worktree |
| `python -m pytest -q -rs` | **974 réussis, 2 ignorés, 0 échec** | pytest-final.log (`test-results/NW-220/pytest-final.log`, preuve locale non versionnée) |
| `flutter build apk --debug --no-pub ...` | **Réussi** | build-final.log (`test-results/NW-220/build-final.log`, preuve locale non versionnée) |
| `git diff --check` / index | **Aucune erreur / index vide** | Contrôle final local |

La commande Python complète utilise `PATH=/tmp/nw220-docker/root/usr/bin:$PATH`
et `DOCKER_CONFIG=/tmp/nw220-docker/config`, puis l'interpréteur du projet.
Les deux tests ignorés sont les archives locales SHOM XYZ absentes (hors sources
de sondes MVP) et la sonde native Nginx non activée par `NOWAVE_TEST_NGINX`.
Le warning restant est la dépréciation Starlette/TestClient liée à httpx.
Les tests de base PostgreSQL hors suite par défaut n'ont pas été lancés ; les
routes marines publiques testées ne dépendent pas de la base métier.
La CI de PR appartient à la phase B et n'a pas été présentée comme exécutée.

Les nouveaux tests couvrent notamment : ordre portuaire conservé contre un nouvel
objet mieux trié, enrichissement à Z10, caches et vrais appels clients simulés en
tests unitaires, absence de token sur ces appels, plafond de concurrence,
réponses 503 jamais mises en cache comme océan vide, reprise d'une réponse
partielle sans remplacement de géométrie, découpage exact des courbes, possession
unique d'un segment frontalier, annulation des tâches de fournisseurs,
séparation des caches MVT/GeoJSON et conservation de la résolution des sondes Z16.
Ces tests unitaires ne sont pas assimilés aux preuves Android ci-dessous.

### Première passe

Relecture des seuils et fournisseurs actuels, tests ciblés puis suites, exécution
de NoWave depuis `lib/main.dart`, matrice fractionnaire aller/retour, examen des
captures et requêtes natives. Défauts constatés et corrigés :

1. Les expressions de chevauchement par objet exposées par Flutter étaient refusées par le moteur Android (« data expressions not supported »). Remplacement par des couches de sécurité séparées, réellement installées et testées.
2. Le satellite/océan du globe atténuait le raster malgré son opacité 1. Placement du raster après cette décoration, puis nouvel examen Z4,99/Z5.
3. Ancien couplage lignes/étiquettes et arrêt EMODnet à Z15 retirés ; anciennes assertions de tests adaptées au nouveau contrat.
4. Consultation par appui long testée dans la vraie application, sans modifier les interactions reports.

### Deuxième passe critique distincte

Reprise du diff et recherche des faux préchargements, identités perdues,
remplacements de géométrie, collisions inter-couches, erreurs prises pour des
vides, doublons aux bords, saturation, rechargement de style et arrière-plan.
Corrections additionnelles avec tests rejoués :

1. Conservation fondée aussi sur le champ géographique réel, pour ne pas retirer une courbe encore visible lors d'une forte inclinaison.
2. Réponses hydrographiques partielles réessayées ; nouvelles identités ajoutées sans remplacer la géométrie déjà récupérée.
3. Points conservés bornés en octets, requêtes suspendues en arrière-plan, annulations comptées une seule fois par requête.
4. Bords de cellules calculés sur une grille canonique et propriété unique des segments exactement frontaliers.
5. Ordre de dessin explicite : dangers physiques prioritaires, couches de sécurité au-dessus des marques ordinaires, reports conservés.
6. Dernier contrôle de résolution : les sondes doivent continuer à récupérer leur résolution native Z16. Correction du plafond auparavant partagé Z14, test de route Z16 et nouvelle compilation/installation avec vérification Android réelle.

Les résultats finaux des suites incluent ces corrections. Aucun commit n'a été
réalisé entre les passes.

## D. Validation sur le téléphone physique

- Appareil détecté : **LGN LX1 / LGN_LX1**, **Android 15, API 35**.
- ID ADB effectivement détecté : **AV5PJV6328H03108**.
- Véritable NoWave `fr.blueway.app`, entrée `lib/main.dart` : **ouverte**.
- Carte accessible : **oui** ; session/profil conservés, GPS réel et boussole actifs.
- Backend métier : `https://api.no-wave.fr/` ; backend marin : code NW-220 local `http://127.0.0.1:8004/`.
- `/health` local : HTTP 200 ; routes GeoJSON et données réelles contrôlées. Pas de test du nouveau mobile uniquement contre un ancien backend de production.
- `adb reverse tcp:8004 tcp:8004` vérifié. Aucun token métier ajouté au client HTTP public marin.
- Réinstallation normale de l'APK, sans désinstallation, `pm clear`, faux GPS, compte ou signalement de recette en production.

Commandes de lancement et de compilation utilisent `.env.json`,
`API_BASE_URL=https://api.no-wave.fr/` et
`MARINE_API_BASE_URL=http://127.0.0.1:8004/`, sans ancienne variable bathymétrique.
Le backend local et le reverse USB restent disponibles pour cette APK.

### Matrice et régions

Matrice réelle aller **et** retour :
`4.99 → 5 → 5.01 → 5.99 → 6 → 7.99 → 8 → 9 → 9.99 → 10 → 11.99 → 12 → 12.99 → 13 → 14 → 15 → 16 → 18`, puis parcours inverse.
Centre principal : longitude **5.93**, latitude **43.08**. Les zooms exacts,
coordonnées, rotation et inclinaison mesurés sont enregistrés avec chaque capture.
Le badge de zoom de l'application arrondit à une décimale : la preuve d'un Z11,99
ou Z12,99 se lit dans le JSON associé. Le bloc latitude/longitude de l'écran est
le **GPS réel**, pas la caméra ; il reste donc en France pendant les essais en
Martinique. Aucun GPS simulé.

Autres zones : Marseille, Toulon, Saint-Mandrier, Porquerolles/Port-Cros ;
Le Marin en Martinique pour les balises de danger isolé disponibles ; Lorient
pour rechercher un exemplaire flottant sans en fabriquer.

Preuve consolidée des seuils et ports : functional-proof.json (`test-results/NW-220/functional-proof.json`, preuve locale non versionnée) : **aucun rendu d'une famille sous son seuil** dans la matrice.
La matrice complète comprend 36 captures et leurs JSON : summary.json (`test-results/NW-220/final-matrix/summary.json`, preuve locale non versionnée).

| Résultat attendu et observé | Capture réelle / données |
|---|---|
| Z4,99 : pas de raster marin ; Z5 : raster opaque visible | Z4,99 (`test-results/NW-220/final-matrix/00-forward-z4.99.png`, preuve locale non versionnée) · Z5 (`test-results/NW-220/final-matrix/01-forward-z5.00.png`, preuve locale non versionnée) |
| Z7,99 : aucun port ; Z8 : représentants présents | Z7,99 (`test-results/NW-220/final-matrix/05-forward-z7.99.png`, preuve locale non versionnée) · Z8 (`test-results/NW-220/final-matrix/06-forward-z8.00.png`, preuve locale non versionnée) |
| Z11,99 : aucune marque ; Z12 : marques présentes | Z11,99 (`test-results/NW-220/final-matrix/10-forward-z11.99.png`, preuve locale non versionnée) · Z12 (`test-results/NW-220/final-matrix/11-forward-z12.00.png`, preuve locale non versionnée) |
| Z12,99 : aucune courbe/sonde ; Z13 : données présentes | Z12,99 (`test-results/NW-220/verified-contours/01-contours-z12.99.png`, preuve locale non versionnée) · Z13 final (`test-results/NW-220/verified-final-map.png`, preuve locale non versionnée) |
| Consultation des ports masqués par collision | Appui long (`test-results/NW-220/extras/longpress-sheet.png`, preuve locale non versionnée) |
| Crédits et licences dans l'interface native | Attributions (`test-results/NW-220/installed-final/credits.png`, preuve locale non versionnée) |

Les captures citées et les ciblages N/E/S/O à Z16 ont été réellement examinés.
Les preuves ne sont pas des images générées ni une application de fixture.

### Ports et identités

Port suivi : `openwaters-harbours:17593805227225`, Saint-Mandrier-sur-Mer,
camera 5.9256917 / 43.0794796. Il reste rendu à Z8, Z9, Z10, Z12, Z14, Z16 et
Z18. Une seule empreinte de géométrie GeoJSON est retrouvée sur la série.
Pour les dix représentants initiaux de la série contrôlée, ceux restant dans le
champ sont respectivement **10, 6, 3, 1, 1, 1, 1** aux paliers 8/9/10/12/14/16/18 :
**aucun port attendu manquant**, aucun nouvel objet ne les remplace.
Les autres sortent du champ lorsque le cadrage se resserre.

Séries et identités : persistence-proof.json (`test-results/NW-220/persistence-proof.json`, preuve locale non versionnée) et série finale ports (`test-results/NW-220/verified-ports/summary.json`, preuve locale non versionnée).
La vérification porte sur les coordonnées conservées et les identités source,
pas sur l'égalité bit à bit de coordonnées arrondies par les tuiles internes du
moteur à deux zooms différents.

### Cardinales et dangers isolés

Dix-huit ciblages à Z12/Z16 couvrent les cardinales fixes et flottantes N/E/S/O
et les balises fixes de danger isolé. Les positions projetées réelles sont
comparées aux identités de `queryRenderedFeatures` : **aucun prioritaire dans le
champ manquant**. Des cardinales se chevauchent avec d'autres cardinales, des
latérales, marques spéciales et feux ; les objets prioritaires restent rendus.
Deux enregistrements sources de danger isolé au Marin sont également rendus
simultanément. Une paire SHOM/Open Waters ne constitue pas à elle seule une
preuve de deux objets physiques distincts ; aucune correspondance nouvelle
fondée seulement sur la proximité n'a été inventée.

Preuve : installed-safety-proof.json (`test-results/NW-220/installed-safety-proof.json`, preuve locale non versionnée) ;
captures dans série de sécurité (`test-results/NW-220/installed-final`, preuve locale non versionnée).
Après le dernier ajustement des sondes Z16, des contrôles de sécurité ciblés ont
également été rejoués sur l'APK finale : verified-safety (`test-results/NW-220/verified-safety`, preuve locale non versionnée).
**Limite :** aucun exemplaire réel de `buoy_isolated_danger` récupéré dans les
zones essayées ; son code, sa couche et son pictogramme sont testés, mais sa
preuve visuelle Android ne peut pas être déclarée faite.

### Conservation des trois courbes réelles

| Profondeur publiée | Identité du fragment suivi | Caméra longitude / latitude | Observation |
|---|---|---|---|
| 50 m | `emodnet:contours-2022:contours.23765@12/2115/1504` | 5.9293 / 43.0637 | Rendue à 13,14,15,16,18 ; même empreinte géométrique |
| 100 m | `emodnet:contours-2022:contours.38196@12/2115/1504` | 5.9313 / 43.0442 | Rendue à 13,14,15,16,18 ; même empreinte géométrique |
| 200 m | `emodnet:contours-2022:contours.30097@12/2115/1504` | 5.9645 / 43.0492 | Rendue à 13,14,15,16,18 ; même empreinte géométrique |

Les trois séries incluent le retour sous Z13 : aucun rendu à Z12,99.
Les nouveaux fragments s'ajoutent sans remplacer les anciens. Les tests de
frontière vérifient la réunion des fragments et l'absence de segment artificiel
doublé. Les comptes de fragments internes retournés par Mapbox ne doivent pas
être confondus avec des objets dupliqués dans le GeoJSON.

Preuves : empreintes et identités (`test-results/NW-220/persistence-proof.json`, preuve locale non versionnée),
50 m (`test-results/NW-220/audit-contours/summary.json`, preuve locale non versionnée),
100 m (`test-results/NW-220/audit-contours100/summary.json`, preuve locale non versionnée),
200 m (`test-results/NW-220/audit-contours200/summary.json`, preuve locale non versionnée).
Le dernier APK, après restitution de la résolution des sondes Z16, a reçu un
nouveau parcours ports et 50 m : courbe finale (`test-results/NW-220/verified-contours/summary.json`, preuve locale non versionnée).
Les couches/coordonnées des courbes de 100/200 m n'ont pas changé dans ce dernier
correctif, qui concerne la résolution des sondes.

### Navigation et réseau

- Zooms lents, sauts et zooms rapides, dézoom et déplacements : exécutés.
- Rotation **90°** et inclinaison **60°**, puis rechargement du style : courbes et données conservées, captures examinées.
- Arrière-plan puis retour : compteur de requêtes public marin **919 avant / 919 pendant / 919 après** la fenêtre de contrôle, données conservées.
- Coupure de la seule redirection marine USB : **45 erreurs de connexion attendues**, pas de faux cache de succès vide. Rétablissement du reverse, temporisation et reprise automatique : objets revenus, **détails d'erreurs courants vides** dans la capture de reprise.
- Aucun changement de réglage réseau global, de permission ou de GPS du téléphone.
- Superposition exacte d'un report NoWave avec une marque de sécurité non produite artificiellement ; ce cas précis n'a pas été exercé en réel. Les tests de régression et les règles de rendu/interactions des reports passent.

Journaux et captures : extras.log (`test-results/NW-220/extras.log`, preuve locale non versionnée),
rechargement (`test-results/NW-220/extras/style-reload.png`, preuve locale non versionnée),
reconnexion (`test-results/NW-220/extras/marine-reconnected.json`, preuve locale non versionnée).

## E. Performances mesurées et périmètre

### Préparation portuaire Z6 — sonde backend réelle

- Une cellule Z6 : **16 lectures réelles de tuiles enfants Z8**, **350 ports** récupérés.
- Cache HTTP persistant : **16 hits, 0 requête réseau amont** sur cette sonde chaude.
- Corps PBF lus : **677142 octets**, durée **490,66 ms**.
- Pic Python tracemalloc de la sonde : **5055319 octets** ; processus de sonde max RSS **75968 Kio**. Ce ne sont pas des mesures de mémoire du téléphone.
- Avec neuf cellules publiques par lot Z6, la borne logique est 144 enfants. Un scénario froid complet de 144 téléchargements amont n'est pas présenté comme mesuré.

Détail : z6-provider-real-probe.json (`test-results/NW-220/z6-provider-real-probe.json`, preuve locale non versionnée).

### Dernière série Android ports/profondeurs après correction Z16

- Réponses GeoJSON réussies dans le journal de mesure : **399**, dont **265 non vides**.
- Corps GeoJSON reçus : **5977603 octets**.
- Latence de ces réponses : médiane **37 ms**, P95 **486 ms**, maximum **874 ms**.
- Requêtes de sondes à la résolution **Z16 réellement non vides : 13**.
- Concurrence client bornée à deux, neuf cellules par famille ; tests de concurrence et traces associés.
- La série longue précédente utilisait au plus **45 snapshots**, **915293 octets** de cache JSON et **1135313 octets** de points conservés dans les instantanés enregistrés, sous les plafonds 12 Mio + 4 Mio.

Mesure finale : verified-performance-summary.json (`test-results/NW-220/verified-performance-summary.json`, preuve locale non versionnée).
Ces octets n'incluent ni les rasters PNG, ni les tuiles du fond Mapbox, ni TLS,
ni les échanges métier, ni tous les flux amont du backend. Les hits du cache
client comptent des consultations de cellules, pas des requêtes réseau évitées
uniques. Aucune mesure réseau totale non disponible n'est inventée.

### Mémoire et fluidité

Un profil réel de la longue série sur l'APK installée donne **817793 Ko PSS**,
**950148 Ko RSS**, un tas Dart de **114281888 octets** et **248064 octets externes**.
Le compteur HWUI global debug indique **914 images janky / 16669 (5,48 %)**.
Une autre séquence plus longue donne 7,84 %, avec chargements et nombreux sauts
volontaires de caméra. Les relevés finaux sont également enregistrés :
mémoire finale (`test-results/NW-220/verified-final-memory.txt`, preuve locale non versionnée),
HWUI final (`test-results/NW-220/verified-final-gfx.txt`, preuve locale non versionnée),
tas Dart final (`test-results/NW-220/verified-final-dart-memory.json`, preuve locale non versionnée).

Ces valeurs globales debug incluent moteur, globe, textures, fond et outil de
recette. Elles ne constituent ni un FPS Flutter/Mapbox de production, ni une
comparaison avec `dev` dans les mêmes conditions. **Absence de régression de
fluidité/mémoire en release non démontrée**, aucun résultat de ce type n'est annoncé.

## F. Anomalies, corrections et limites

| Cas | Cause / gravité | Impact et état |
|---|---|---|
| Expressions de chevauchement refusées sur Android | Propriété exposée dans Flutter mais expression non supportée par le moteur ; bloquant initial | Corrigé par couches de sécurité séparées, installation native et ciblages vérifiés |
| Raster Z5 atténué | Ordre de couches du décor globe ; fonctionnel | Corrigé, comparaison Z4,99/Z5 examinée |
| Courbes dépendantes des étiquettes et arrêt Z15 | Ancien contrat de rendu ; bloquant initial | Corrigé, lignes séparées et trois courbes conservées jusqu'à Z18 |
| Géométries en bord de champ / cache partiel figé | Voisinage limité et conservation sans rafraîchissement ; fonctionnel | Corrigé par champ réel, fragments fixes et ajouts d'identités ; tests et navigation rejoués |
| Plafond des sondes Z14 au lieu de leur Z16 existant | Plafond partagé avec les autres familles ; régression détectée avant rapport | Corrigé, tests de route/client et nouveaux téléchargements Android Z16 non vides |
| Open Waters : 15 réponses locales 503 lors de certains essais de ports Marseille Z14 | Fournisseur/transport indisponible ; sonde directe équivalente en **ReadTimeout après 6139,88 ms** ; cause amont détaillée à confirmer | **Non résolu côté source**. Ce ne sont pas des tuiles vides valides. Les marques officielles peuvent rester disponibles, sans preuve d'exhaustivité portuaire sur ces tuiles. À retester lorsque la source répond |
| `buoy_isolated_danger` sans exemplaire réel récupéré | Disponibilité des données dans les zones choisies ; preuve manquante | Code et tests présents, pas de preuve visuelle Android de cette sous-famille ; **critère partiel** |
| Chevauchement exact de plusieurs pictogrammes | Limite de lisibilité au même pixel | Les enregistrements prioritaires restent rendus ; appui long pour accès. Aucune promesse de lecture séparée à coordonnées exactement identiques |
| Comparaison performance release / dev | Profil comparatif non réalisé | Mémoire et HWUI mesurés en debug ; **validation performance partielle** |
| Deux premiers tests Compose en échec WSL | Outil indisponible dans PATH | Résolu par les vrais outils isolés ; **974 tests finaux réussis** |
| Jeton public Mapbox affiché dans une sortie de diagnostic de processus | Erreur de manipulation pendant l'analyse | Aucune copie du jeton dans le diff ou les nouveaux fichiers de revue. `.env.json` non modifié, aucune publication |

Le diagnostic fournisseur est conservé dans
openwaters-outage-probe.json (`test-results/NW-220/openwaters-outage-probe.json`, preuve locale non versionnée).
Les 503 Open Waters de la série détaillée sont séparés des 45 erreurs volontaires
de la coupure USB. Aucun 404 de nouveau contrat n'est présenté comme une réussite.
Les mesures et captures restent locales et ignorées par Git.

Budgets et couverture restent explicites : le centre et le voisinage immédiat
sont préparés, pas la planète entière ; une vue très étendue/inclinée peut
dépasser neuf cellules. En saturation on refuse de nouveaux snapshots sans
supprimer les géométries utiles déjà conservées. La couverture intégrale de
chaque vue et le comportement en saturation extrême ne sont pas démontrés.
Aucune profondeur, courbe, couleur ou catégorie manquante n'est fabriquée.

## G. Verdict et limite d'autorisation

**PARTIELLEMENT VALIDÉ.**

| Élément indispensable | État et preuve |
|---|---|
| Conservation des ports sélectionnés à Z8 | **Démontrée** sur le parcours contrôlé, identités et coordonnées vérifiées jusqu'à Z18 ; disponibilité Open Waters à retester sur les tuiles Marseille en échec |
| Visibilité des cardinales et dangers isolés à Z12 | **Démontrée pour les huit cas de cardinales et les balises fixes de danger isolé**, y compris chevauchements ; **preuve native de la bouée de danger isolé manquante** |
| Conservation stricte des isobathes au zoom avant | **Démontrée sur trois courbes EMODnet réelles 50/100/200 m**, identités et géométries constantes de Z13 à Z18, style reload et navigation contrôlés |
| Fonctionnement réel sur Android physique | **Démontré**, vraie NoWave ouverte, carte parcourue, APK installée comparée par SHA-256, compte et GPS préservés |

Les limites de source et preuves manquantes restent ouvertes ; elles ne sont
pas transformées en critères réussis par les tests automatisés verts.
L'implémentation et les preuves sont conservées dans le worktree, prêtes pour
revue et corrections éventuelles. **Aucun commit, push, PR, changement Linear,
merge ou déploiement n'a été effectué.**

Conformément à la consigne de phase A, la publication attend une autorisation
explicite après lecture de ce rapport. Si une publication partielle ou une PR
Draft est souhaitée avec les limites ci-dessus, elle nécessite un accord
explicite adapté ; une autorisation ne transforme pas les critères partiels en
validation complète. Le passage In Review ne sera pas fait sur une PR non prête.

## Annexe — comptes de rendu natif de la matrice complète

Caméra principale 5.93 / 43.08. Ces comptes peuvent diminuer au zoom lorsque des
objets sortent du champ ; ils ne prouvent pas seuls une perte d'identité.
Les « marques » regroupent ici les pictogrammes et dangers ; les « profondeurs »
regroupent lignes, annotations et sondes, pas seulement des objets uniques.

| Capture / sens | Zoom réel | Ports rendus | Marques/dangers rendus | Profondeurs rendues |
|---|---:|---:|---:|---:|
| 00-forward-z4.99 | 4.99 | 0 | 0 | 0 |
| 01-forward-z5.00 | 5.00 | 0 | 0 | 0 |
| 02-forward-z5.01 | 5.01 | 0 | 0 | 0 |
| 03-forward-z5.99 | 5.99 | 0 | 0 | 0 |
| 04-forward-z6.00 | 6.00 | 0 | 0 | 0 |
| 05-forward-z7.99 | 7.99 | 0 | 0 | 0 |
| 06-forward-z8.00 | 8.00 | 10 | 0 | 0 |
| 07-forward-z9.00 | 9.00 | 7 | 0 | 0 |
| 08-forward-z9.99 | 9.99 | 4 | 0 | 0 |
| 09-forward-z10.00 | 10.00 | 6 | 0 | 0 |
| 10-forward-z11.99 | 11.99 | 7 | 0 | 0 |
| 11-forward-z12.00 | 12.00 | 6 | 60 | 0 |
| 12-forward-z12.99 | 12.99 | 1 | 42 | 0 |
| 13-forward-z13.00 | 13.00 | 1 | 41 | 31 |
| 14-forward-z14.00 | 14.00 | 1 | 19 | 13 |
| 15-forward-z15.00 | 15.00 | 0 | 16 | 1 |
| 16-forward-z16.00 | 16.00 | 0 | 8 | 0 |
| 17-forward-z18.00 | 18.00 | 0 | 0 | 0 |
| 18-reverse-z18.00 | 18.00 | 0 | 0 | 0 |
| 19-reverse-z16.00 | 16.00 | 0 | 8 | 0 |
| 20-reverse-z15.00 | 15.00 | 0 | 16 | 1 |
| 21-reverse-z14.00 | 14.00 | 1 | 19 | 13 |
| 22-reverse-z13.00 | 13.00 | 1 | 41 | 52 |
| 23-reverse-z12.99 | 12.99 | 1 | 42 | 0 |
| 24-reverse-z12.00 | 12.00 | 6 | 60 | 0 |
| 25-reverse-z11.99 | 11.99 | 7 | 0 | 0 |
| 26-reverse-z10.00 | 10.00 | 6 | 0 | 0 |
| 27-reverse-z9.99 | 9.99 | 4 | 0 | 0 |
| 28-reverse-z9.00 | 9.00 | 5 | 0 | 0 |
| 29-reverse-z8.00 | 8.00 | 4 | 0 | 0 |
| 30-reverse-z7.99 | 7.99 | 0 | 0 | 0 |
| 31-reverse-z6.00 | 6.00 | 0 | 0 | 0 |
| 32-reverse-z5.99 | 5.99 | 0 | 0 | 0 |
| 33-reverse-z5.01 | 5.01 | 0 | 0 | 0 |
| 34-reverse-z5.00 | 5.00 | 0 | 0 | 0 |
| 35-reverse-z4.99 | 4.99 | 0 | 0 | 0 |
