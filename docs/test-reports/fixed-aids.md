# NoWave — balises fixes, phares et feux

Mission du 17 octobre 2026. Extension du pipeline et de la carte existants,
sans nouvelle architecture ni nouvel endpoint. Validation sur l’application réelle.

## Git initial

Branche attendue et constatée : `feature/marine-bathymetry`.
HEAD attendu et constaté : `91018156 feat(map): add multi-source marine data and improve map visuals`.
Les trois commandes imposées ont été exécutées avant modification :
[git-initial.txt](evidence/fixed-aids/git-initial.txt).
Le statut initial ne contenait que les cinq dossiers de preuves non suivis des
missions précédentes : `buoys/`, `map-visual/`, `marine-sources/`, `neutral-texture/`,
`water-texture/`. Ils ont été conservés.

## Analyse de l’existant

Fichiers inspectés : `map_tiles.py`, `marine_tiles.py`, `marine_merge.py`, `marine.py`,
`marine_tile.py`, providers/normalisation/encodage/runtime/cache/catalogues dans
`infrastructure/marine/`, outils de catalogue et fixtures/tests marins ; côté mobile,
`marine_tiles.dart`, `buoy_layer.dart`, `port_layer.dart`, `map_screen.dart`,
`MarineMapController`, `WaterTextureLayer`, générateur/assets de bouées et tests carte.

Le backend n’admettait que cinq types de bouées. Le filtre Open Waters et la sélection
des classes SHOM/NOAA écartant les autres aides, ajouter seulement des icônes Flutter
n’aurait pas suffi. Le modèle de points, les fournisseurs, la fusion conservative,
la couverture géographique et l’encodeur MVT existants permettent l’extension.
La source mobile `nowave-buoys` / source-layer `seamark` est partagée : aucune seconde
requête mobile pour les nouvelles aides. Le filtre de rendu des bouées reste inchangé.

## Sources et catégories réellement vérifiées

Vérification réseau explicite du GetCapabilities SHOM, des métadonnées `/layers`
NOAA aux six échelles et de quatre tuiles Open Waters, puis des tuiles NoWave finales.
Les extraits et inventaires figurent dans [les preuves](evidence/fixed-aids/).

| Source | Catégories et décision |
| --- | --- |
| SHOM | `bcncar`, `bcnisd`, `bcnlat`, `bcnspp`, `lights`, `lndmrk` réellement publiés. Balises cardinales, danger isolé, latérales, spéciales, feux et phares strictement qualifiés intégrés, priorité 100. Pas de `bcnsaw` dans ce service : aucune requête inventée pour ce nom. |
| NOAA | 29 entrées supplémentaires extraites des six catalogues réels : `Beacon_*`, `Light_point`, `Landmark_point`. Cardinales/danger isolé disponibles notamment à l’échelle approach ; les cinq classes ne sont pas supposées présentes à chaque échelle. Priorité existante 100 + rang d’échelle conservée. |
| Open Waters / OSM | Balises cardinales/latérales/spéciales et `light_major` / `light_minor` réellement observés dans les tuiles testées. Les deux types lumineux deviennent `light`, jamais automatiquement `lighthouse`. Fallback permanent conservé, priorité 10. Aucun phare Open Waters autonome n’a été confirmé dans ces quatre extraits ; les phares validés ici proviennent de SHOM/NOAA. |
| Canada / CHS | Pas d’adapter activé : extraction vectorielle exhaustive toujours non validée dans l’intégration précédente. La relecture du portail public pendant cette mission a renvoyé 403 ; aucune nouvelle capacité n’est annoncée. Fallback mondial conservé. |
| Australie / AMSA–AHO | Conditions officielles relues : Spatial@AMSA demeure CC BY-NC 3.0 AU ; l’AHO demande un accord de licence. Aucune autorisation supplémentaire disponible : pas de fausse intégration, fallback conservé. |
| NZ / LINZ | Aucune clé disponible, conformément à la réponse utilisateur précédente. La page documentaire a également renvoyé 403 durant cette relecture. Aucune nouvelle couche LINZ activée ou catégorie prétendument vérifiée ; fallback conservé. |

Le contrat et le rendu couvrent les cinq `beacon_*` demandés, `lighthouse` et `light`.
La présence d’une classe ne constitue pas une preuve de présence d’objets dans chaque
port : danger isolé et eaux saines fixes sont absents des quatre tuiles locales étudiées.
Deux requêtes limitées à **un objet** ont toutefois confirmé des données qualifiées :
Caye Ronde (SHOM `bcnisd`, noir/rouge/noir horizontal) et Buttonwood Harbor Channel
Daybeacon A (NOAA safe water, rouge/blanc vertical). Ces extraits réels sont testés.
L’exemple NOAA approach danger isolé sans couleur reste volontairement non qualifié.

Qualification d’un phare : uniquement une tour `LNDMRK` avec CATLMK=17 / `tower`
et FUNCTN contenant 33 / `light support`. Un nom, une hauteur, une portée ou une
fonction générique `lighting` ne suffit pas. Les autres landmarks et bâtiments
non qualifiés ne sont pas importés. Les phares encodés autrement, notamment BUISGL,
ne sont pas annoncés comme intégrés. Référence : règle de qualification décrite
par l’[IHO, UOC §12.3.2](https://docs.iho.int/iho_pubs/draft_pubs/Draft_S-57_Appendix_B.1_Annex_A_UOC_e4.0.0.pdf)
et corroborée par les attributs réels de Cap Cépet / Cape Florida.

Références de services : [SHOM WFS](https://services.data.shom.fr/static/help/fr/Shom_WFS.html),
[NOAA harbour](https://encdirect.noaa.gov/arcgis/rest/services/encdirect/enc_harbour/MapServer),
[Open Waters](https://github.com/openwatersio/seamap),
[AMSA](https://www.operations.amsa.gov.au/spatial/DataServices/Copyright),
[AHO](https://www.hydro.gov.au/hydrography/licensing).

## Modèle, normalisation et fusion

`SeamarkFeature` conserve les champs existants et ajoute : `light_color`,
`light_character`, `light_range`, `light_group`, `light_period`, `light_details`.
Les codes/labels S-57 LITCHR officiels sont conservés tels que publiés, avec SIGGRP,
SIGPER et VALNMR. Les caractéristiques OSM explicites et les valeurs lumineuses
numérotées restent conservées dans `light_details` sans géométrie de secteurs.
Une portée absente reste absente ; le défaut synthétique de **9 M** d’Open Waters
n’est pas importé comme une mesure. Les couleurs multiples ne deviennent pas un
secteur lumineux supposé : la petite lanterne prend un rendu neutre.

Les formes fixes BCNSHP utilisent leur propre vocabulaire, distinct de BOYSHP.
Topmarks SHOM : jointure par identifiant publié ; feux SHOM : lien explicite `lights`.
NOAA : jointure de topmark/feu uniquement à coordonnées, cellule et échelle identiques ;
plusieurs feux colocalisés ne sont pas synthétisés en une fausse caractéristique unique.
Le nom, la source, l’identifiant, la priorité, l’échelle, les dates et les provenances
restent disponibles dans les propriétés MVT.

La fusion conserve son exigence de même type et de corroboration sémantique/spatiale.
Une bouée, une balise, un phare et un feu ne fusionnent pas sur la seule colocalisation.
Pour les feux/phares, des caractéristiques lumineuses contradictoires empêchent aussi
une fusion arbitraire. Les conflits restent observables ; aucune garantie d’absence
absolue de doublons n’est revendiquée. Les règles de fusion des ports/bouées sont conservées.

## IALA A/B

Le nouveau rendu reprend exactement les expressions de qualification des bouées,
en remplaçant seulement les types et identifiants de dessins par les variantes fixes.

- SHOM : système de l’autorité et de ses territoires déjà documenté dans le pipeline,
  sans dépendance au téléphone ; métropole A, territoires américains concernés B.
- NOAA : B, et MARSYS explicite prioritaire lorsqu’il est renseigné.
- Open Waters : système explicite conservé, notamment `seamark:beacon_lateral:system`.
  Sans système connu, couleur publiée conservée sans déduire un côté ou supposer A.
- Contradiction ou attributs insuffisants : petit fallback sombre. Les couleurs/motifs
  calculés par défaut en amont ne qualifient pas les nouveaux beacons.

Exemples réels testés : NOAA port + vert / starboard + rouge, en IALA B ;
Caye Ronde en Martinique reste également B. Sur le téléphone, la position GPS reste
en France alors que la carte consultée à Miami utilise bien les objets NOAA B :
le routage et le système ne sont pas déduits du GPS.

## Rendu, zoom et collisions

21 PNG originaux, géométrie SVG simple générée par `make_fixed_aid_icons.py`,
licence CC0 documentée dans les assets. Aucune illustration ni code GPL Open Waters
incorporé ; la lecture de son profil sert seulement à vérifier le contrat de données.
Aucune nouvelle dépendance mobile. Régénération en dossier temporaire : PNG identiques.

Balise fixe : support vertical étroit, pied au sol, aucune coque ni vague ; bandes
et topmarks cardinaux corrects. Phare : petite tour identifiable, plus prioritaire
que les autres aides fixes. Feu : petit point coloré avec quatre traits très courts,
sans texte, secteur ni effet animé. Neutral : petit point sombre prudent.

| Affichage | Seuil minimum |
| --- | ---: |
| Phare qualifié | z10 |
| Feu avec portée explicitement ≥10 M | z11 |
| Balise cardinale / danger isolé qualifiée | z12 |
| Autres balises qualifiées | z13 |
| Support non qualifié, point secondaire | z13 |
| Autres feux, y compris portée inconnue | z14 |

Sous z10, aucune nouvelle aide et aucune requête amont marine, comme précédemment.
Taille des phares : .85 à z10, 1.05 à z13, 1.25 à z16, 1.35 à z18.
Autres aides : .65 à z11, .85 à z14, 1.05 à z17, 1.10 à z18.
Les dessins fixes restent plus étroits/petits que les bouées ×2 existantes.

Six couches utilisent le même slot `top`, insérées explicitement sous les bouées :
points de supports inconnus → feux locaux → feux de plus grande portée → balises
qualifiées locales → balises qualifiées principales → phares → **bouées existantes**.
Les reports sans slot restent au-dessus. `iconAllowOverlap=false`,
`iconIgnorePlacement=false`, padding 2. Dans chaque couche fixe, priorité de source
d’abord (`-1000 × source_priority`), puis portée explicite pour départager.
Un support inconnu peut ainsi céder sa place à son feu qualifié, sans déplacement
artificiel de la géométrie. Une balise qualifiée reste prioritaire sur son propre feu.
Ces choix ont été ajustés sur les essais réels de Miami, pas seulement sur des mocks.

## Validation France et USA

Application `fr.blueway.app` réelle, session conservée, LGN LX1 Android 15/API 35,
ADB `AV5PJV6328H03108`. APK debug compilé avec `.env.json` et le backend marin
local de cette mission, port **8004**, puis installé et lancé à froid.
Aucun déploiement du backend distant, aucun GPS simulé et aucune donnée factice
injectée dans l’application. Les captures sont des PNG ADB non retouchés, réellement
ouverts et examinés dans leur version finale.

| Capture | Contrôle visuel |
| --- | --- |
| [toulon-cardinal-phare-z15_5.png](evidence/fixed-aids/toulon-cardinal-phare-z15_5.png) | Banc de l’Âne : cardinale ouest étroite, cônes pointes jointes, jaune/noir/jaune ; phare de Petite Passe, feu discret et bouées jaunes conservés. |
| [marseille-if-cardinal-z13_7.png](evidence/fixed-aids/marseille-if-cardinal-z13_7.png) | Île d’If, Sourdaras et Canoubier : phare + cardinales distincts des bouées, texture/bathymétrie et côte lisibles. |
| [miami-iala-b-z16.png](evidence/fixed-aids/miami-iala-b-z16.png) | Fishermans Channel : balises rouges/vertes fixes, vraies données NOAA B, petits points pour les supports non qualifiés. |
| [miami-port-z14.png](evidence/fixed-aids/miami-port-z14.png) | Vue portuaire locale : densité progressive, quais et labels restent lisibles. |
| [miami-feux-z16.png](evidence/fixed-aids/miami-feux-z16.png) | Feux NOAA près du pont : petits points lumineux sobres, réellement visibles devant les supports inconnus colocalisés. |
| [cape-florida-phare-feux-z15_5.png](evidence/fixed-aids/cape-florida-phare-feux-z15_5.png) | Cape Florida Light NOAA : phare qualifié et identifiable. Son feu colocalisé cède sa place au symbole de phare. |
| [miami-regional-z11.png](evidence/fixed-aids/miami-regional-z11.png) | Très peu de nouvelles aides : phare visible, balises locales et petits feux masqués par seuil ; bouées existantes inchangées. |
| [toulon-port-z17_5.png](evidence/fixed-aids/toulon-port-z17_5.png) | Bouées rouge/verte ×2 conservées, ouvrages et fond marin intacts. |
| [globe-z1_5.png](evidence/fixed-aids/globe-z1_5.png) | Aucune nouvelle aide à faible zoom ; badge Z et fond marin conservés. |
| [gps-arrival-z15_5.png](evidence/fixed-aids/gps-arrival-z15_5.png) | Recentrage depuis le globe vers la vraie position, arrivée locale, position et reports lisibles. |

Les requêtes natives identifient les objets réellement rendus et leur source :
Banc de l’Âne `shom:bcncar:FR000002390400001`, Sourdaras/Canoubier SHOM,
Cape Florida `noaa:harbour:26:62971`, et latérales NOAA avec `navigation_system=IALA_B`.
Les comptes MVT sont des fragments techniques avec buffer, pas des comptes absolus
uniques de tous les objets d’un port.

Tuiles z12 vérifiées sans source dégradée : Toulon 2115/1503, Marseille 2108/1500,
Miami 1135/1744, Cape Florida 1136/1745. Elles contiennent respectivement des balises,
feux et phares officiels avec les fallbacks conservés. Voir
[live-tiles.json](evidence/fixed-aids/live-tiles.json),
[native.json](evidence/fixed-aids/native.json),
[manifest des captures](evidence/fixed-aids/screenshots.json) et
[appareil / APK](evidence/fixed-aids/device.json).

Les temps des probes incluent des caches HTTP déjà alimentés ; ils ne sont pas un
benchmark de démarrage à froid. Certaines premières prises sans objets ont été
écartées et recapturées après réception des tuiles ; une absence pendant chargement
n’a pas été présentée comme un succès de validation.

## Tests

| Commande | Résultat final |
| --- | --- |
| `.venv/bin/ruff check backend` | Réussi |
| `PYTHONPATH=backend /tmp/nowave-marine/py312/bin/python -m pytest` | **691 tests réussis**, un avertissement Starlette/httpx préexistant |
| `dart format --output=none --set-exit-if-changed lib test` depuis mobile | 164 fichiers, aucun changement requis |
| `flutter analyze` | Aucun problème |
| `flutter test test/features/map/data/fixed_aid_layer_test.dart` | 6 tests réussis |
| `flutter test` | **477 tests réussis** |
| `flutter build apk --debug --dart-define-from-file=.env.json --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/ --dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png` | APK construit, installé et testé |
| `git diff --check` | Réussi, sortie vide |

Les tests couvrent les vrais extraits France/USA, les classes rares qualifiées,
l’exclusion des landmarks non phares, IALA B, les caractéristiques lumineuses,
les valeurs manquantes/défauts Open Waters, la fusion de feux contradictoires,
l’encodage MVT, les symboles/seuils/collisions, les installations concurrentes,
la reprise après panne et le reload. Les tests existants des bouées/ports/GPS/Z passent.
Aucun hack ni nouvelle dépendance pour faire passer les tests. Le warning de migration
Kotlin des plugins préexistait et n’empêche pas la build. Les journaux finaux sont
conservés : [backend](evidence/fixed-aids/backend-tests.log),
[Flutter](evidence/fixed-aids/mobile-tests.log),
[analyse](evidence/fixed-aids/analyze.log), [format](evidence/fixed-aids/format.log),
[build](evidence/fixed-aids/build.log) et [lint](evidence/fixed-aids/backend-lint.log).

## Revue 1 et corrections

Relecture du diff et des données de bout en bout :

1. Suppression de l’usage de la portée synthétique Open Waters 9 M ; conservation
   des attributs lumineux explicites, y compris numérotés, et qualification prudente
   des couleurs/motifs des nouveaux beacons.
2. Priorité de source ajoutée au tri des symboles, avant la portée : les cardinales
   SHOM conservées en conflit passent effectivement devant le fallback au placement.
3. Essais NOAA : séparation du placement des supports inconnus, sous les feux,
   pour ne pas masquer une lumière réellement qualifiée derrière un point de support.
   Ajout du test de cette hiérarchie puis nouvelle build.
4. Erreur d’import pendant un nettoyage Python (`math`/`replace`) corrigée ; suite
   backend relancée avec succès. Les fixtures de classes rares ont été ajoutées,
   puis la suite complète relancée.
5. Captures précoces pendant chargement remplacées par des prises après réception
   des données. Le style final est vérifié sur l’APK reconstruit, pas seulement après hot reload.

## Revue 2 depuis la demande

Seconde passe séparée menée par le même agent, depuis les exigences initiales :
balises fixes distinctes, sept types demandés sans ajout d’autres objets, phares
strictement qualifiés et réellement visibles, feux discrets visibles en France/USA,
IALA A/B et inconnus prudents, densité progressive, priorité des bouées, sources
nationales et fallback conservés, aucune donnée inventée.

Vérification des empreintes de l’état initial : code et assets des bouées, dont
neutral et taille ×2, PortLayer et provider IGN, texture, bathymétrie, badge Z et
halo jaune sont inchangés. Dans `map_screen.dart`, seules l’instanciation et
l’installation de la couche sont ajoutées ; GPS, coordonnées, reports et navigation
ne changent pas. Les dossiers de preuves antérieurs sont préservés.
Le test natif de masquage/restauration des nouvelles couches contrôle aussi les
bouées réellement rendues ; le contrôle GPS vérifie l’arrivée et le retour en vue libre.
Les empreintes confirment **766 fichiers préexistants inchangés sur 778** ; les
12 autres correspondent aux modifications attendues de cette mission. Inventaire :
[preserved-files.json](evidence/fixed-aids/preserved-files.json).
À z14, le masquage puis la restauration des six couches fixes laissent exactement
les mêmes deux identifiants de bouées rendus. Après rechargement réel du style,
chaque couche fixe est présente une seule fois et la source partagée reste unique.
Depuis le globe, le bouton GPS arrive à z15.5 sur le fix réel ; après déplacement
manuel, le viewport reste libre (`following=false`, `IdleViewportState`).
Aucun écart supplémentaire après les corrections et la validation finale.

## Fichiers modifiés et Git final

Backend : domaine `marine.py`, normalisation/providers, catalogue NOAA/métadonnées,
tri de fusion spécifique aux feux, outil de rafraîchissement, fixtures et tests.
Mobile : nouveau `fixed_aid_layer.dart`, génération/assets/documentation des icônes,
entrée d’assets dans pubspec, installation dans MapScreen et tests.
Documentation : architecture mise à jour, présent rapport et preuves.
L’inventaire exact figure dans [changed-files.json](evidence/fixed-aids/changed-files.json).

Sorties intégrales : [git-final.txt](evidence/fixed-aids/git-final.txt), avec
`git status --short`, `git diff --stat`, `git diff --check`, branche et HEAD finaux.
Le diff Git n’inclut pas les fichiers non suivis ; le dossier de preuves contient
également le diff de mission, l’inventaire des nouveaux fichiers et les empreintes
des fichiers préexistants préservés.

**AUCUN COMMIT — AUCUN PUSH — AUCUNE PR.**
Aucun reset, restore, rebase ou amend, aucune suppression des preuves locales.
