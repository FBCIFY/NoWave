# NoWave — Littoral et aides à la navigation — 18 octobre 2026

> Rapport historique : la mention de palette inchangée décrit l'état du 18
> octobre. La palette bathymétrique a été remplacée le 22 octobre par
> `marine-palette-3` ; voir [la correction de palette](NW-220-color-palette.md).

Validation locale sur `feature/marine-bathymetry`. Le masque corrige les pixels raster côtiers placés sur terre dans les tuiles analysées ; aucun débordement bleu perceptible sur les terres des vues finales vérifiées, notamment Z6 et Z9. Le dégradé en mer est conservé. Les balises latérales à bandes grises disposent désormais de leurs icônes qualifiées.

L’audit ne revendique pas une exhaustivité nautique mondiale. Il distingue absence fournisseur, emprise de caméra, seuil de zoom, qualification incomplète, découpage de tuile et collisions. À Porquerolles, le support masqué dans la vue Z14 est visible à Z15,8. Les données numériques européennes restent EMODnet et les américaines NOAA, conformément au choix utilisateur antérieur.

## A. Git initial

Branche : `feature/marine-bathymetry`. HEAD : `204373489f47fbd41993960f245aaf20ff14ba1d` (`20437348`). État réellement constaté avant intervention : **21 fichiers suivis modifiés et 35 non suivis**, 705 fichiers suivis ou non ignorés au total. Les changements hydrographiques antérieurs étaient bien présents.

Une copie externe des **705 fichiers**, avec empreintes SHA-256, état Git, diff et index, a été conservée avant édition : `/home/palms/nowave-snapshots/coastline-seamarks-20261018T140038Z/`. Les fichiers ignorés de preuves antérieures sont conservés sur place ; `.env.json` a fait l’objet d’une copie privée sans exposition des valeurs.

Documents lus : [rapport précédent](marine-final-2026-10-18.md), [sources marines](../architecture/marine-sources.md), [hydrographie](../architecture/hydrography.md), [EMODnet](../architecture/emodnet-depths.md) et rapports hydrographiques antérieurs présents. Aucun reset, restore destructif, clean, rebase, amend, commit, push ou PR.

## B. Cause du bleu

Les comparaisons contrôlées Android Z6 et Z9 ont séparé fond Standard, raster seul, texture seule et ensemble. Le raster WMS possède bien un alpha, mais son contour n’est pas aligné sur la géométrie côtière OSM : certains pixels dont le centre est terrestre restent opaques. L’interpolation linéaire du raster peut rendre cette frange plus visible. Les couleurs et ombres terrestres qui restent avec le fond seul ne sont pas un débordement marin.

La texture seule suit l’eau dans les vues comparées ; elle n’est pas la cause démontrée de la frange. Le slot raster BOTTOM, le slot texture, le fond d’eau Standard et les couches de relief n’ont pas été déplacés pour cacher le défaut.

**Limite de reproduction :** le large recouvrement intérieur supposé vers La Crau/Hyères n’a pas été reproduit comme un raster opaque sur toute cette emprise. Les pixels intérieurs sondés étaient déjà transparents. Le défaut effectivement mesuré est côtier ; ne pas interpréter ce rapport comme la preuve d’un ancien débordement massif partout sur l’arrière-pays.

Preuves avant : [before-toulon-z6.png](../../test-results/coastline-seamarks-2026-10-18/before-toulon-z6.png), [before-toulon-z9.png](../../test-results/coastline-seamarks-2026-10-18/before-toulon-z9.png). Décomposition : [diagnostic-z6-base-only.png](../../test-results/coastline-seamarks-2026-10-18/diagnostic-z6-base-only.png), [diagnostic-z6-raster-only.png](../../test-results/coastline-seamarks-2026-10-18/diagnostic-z6-raster-only.png), [diagnostic-z9-base-only.png](../../test-results/coastline-seamarks-2026-10-18/diagnostic-z9-base-only.png), [diagnostic-z9-raster-only.png](../../test-results/coastline-seamarks-2026-10-18/diagnostic-z9-raster-only.png), [diagnostic-z9-texture-only.png](../../test-results/coastline-seamarks-2026-10-18/diagnostic-z9-texture-only.png). PNG originaux et corrigés conservés dans le même répertoire.

## C. Correction littorale

Nouveau module backend `coastline.py`, appelé par l’endpoint PNG existant. Il utilise les polygones réels `ocean` de Shortbread/OSM, plus `water_polygons` de type dock/canal pour les bassins. Les lacs et glaciers ne sont pas assimilés à l’océan. La géométrie provient du service déjà utilisé pour l’infrastructure portuaire : pas de nouveau fournisseur de profondeurs.

Étapes : décodage MVT avec son extent publié ; passage des coordonnées locales y vers le haut à l’image y vers le bas ; union des surfaces avec conservation des trous insulaires ; rasterisation 4× ; réduction BOX ; limitation aux pixels dont le centre appartient réellement à l’eau ; multiplication de l’alpha source par ce masque. Le décalage de demi-échantillon place correctement les centres des sous-pixels. Les RGB sont conservés exactement. Pas de seuil de profondeur, de dilatation, d’érosion volontaire du trait de côte ou de couleur terrestre de camouflage.

La grille XYZ Web Mercator est commune aux tuiles adjacentes. Les îles coupant une frontière sont testées des deux côtés. Les traitements CPU se font hors de la boucle asyncio. Une image source entièrement transparente évite le téléchargement et le calcul du masque. Une indisponibilité de géométrie retourne 503 plutôt qu’un PNG non masqué.

Le SDK installé est Mapbox Flutter **2.30.1**, natif **11.30.1**. La [spécification officielle des couches clip](https://docs.mapbox.com/style-spec/reference/layers/#clip) ne propose pas le raster parmi `clip-layer-types` : aucune API Flutter de clipping raster inventée. Le masque est donc appliqué au PNG backend.

Palette inchangée : `#E6F7FD`, `#D2F0FB`, `#B7E4F7`, `#8FD0EE`, `#5CB3DF`, `#1E6FA8`. Le raster reste une visualisation, sans conversion de couleur en sonde chiffrée.

Licence : OSM/ODbL 1.0, attribution ajoutée à `/marine-sources` et aux fixtures. Références : [schéma Shortbread](https://shortbread-tiles.org/schema/1.0/), [politique officielle des tuiles vectorielles OSM](https://operations.osmfoundation.org/policies/vector/).

## D. Contrôle des zooms

Caméras régionales avant/après : centre `(6.03, 43.10)`, orientation 0°, inclinaison 0°, style Standard identique. Les coordonnées affichées dans le widget sont celles du GPS réel, et ne remplacent pas le centre de caméra consigné dans les preuves.

| Zoom | Vue finale ouverte | Contrôle |
|---|---|---|
| Z4 | [final-toulon-z4.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z4.png) | Vue globale ; atténuation historique du raster à Z4 conservée |
| Z6 | [final-toulon-z6.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z6.png) | Critère impératif : littoral net, dégradé conservé au large |
| Z7 | [final-toulon-z7.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z7.png) | Transition côtière et dégradé vérifiés |
| Z8 | [final-toulon-z8.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z8.png) | Transition côtière et dégradé vérifiés |
| Z9 | [final-toulon-z9.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z9.png) | Toulon, La Crau et Hyères : pas de bleu marin perceptible sur les terres |
| Z10 | [final-toulon-z10.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z10.png) | Transition côtière et dégradé vérifiés |
| Z12 | [final-toulon-z12.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z12.png) | Côte du Pradet ; courbes et labels présents |
| Z14 | [final-toulon-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z14.png) | Vue terrestre du Pradet ; complétée par le port de Toulon ci-dessous |
| Z16 | [final-toulon-z16.png](../../test-results/coastline-seamarks-2026-10-18/final-toulon-z16.png) | Vue intérieure du Pradet ; preuve côtière complétée par Vauban ci-dessous |

Compléments côtiers : [final-vauban-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-vauban-z14.png) et [final-vauban-z16.png](../../test-results/coastline-seamarks-2026-10-18/final-vauban-z16.png) au centre `(5.925, 43.1145)` ; [final-hyeres-z9.png](../../test-results/coastline-seamarks-2026-10-18/final-hyeres-z9.png) `(6.14,43.12)` ; [final-frejus-z12.png](../../test-results/coastline-seamarks-2026-10-18/final-frejus-z12.png) `(6.758,43.422)` ; [final-marseille-z9.png](../../test-results/coastline-seamarks-2026-10-18/final-marseille-z9.png) `(5.308,43.278)` ; Antibes et Port-Cros dans K. Les vues Z14/Z16 du Pradet seules ne sont pas revendiquées comme preuve du littoral toulonnais.

Les captures retenues ont été réellement ouvertes et examinées ; inventaire et empreintes : [captures-reviewed.json](../../test-results/coastline-seamarks-2026-10-18/captures-reviewed.json). Pas de bleu marin perceptible sur les terres dans ces vues ; texture discrète sur l’eau. Le relief, les cours d’eau du fond Standard et le halo GPS restent distincts du raster marin. Une absence d’artefact dans ces vues n’est pas une garantie sur toutes les côtes mondiales.

## E. Tests des tuiles

Comparaison des mêmes PNG sources avec le masque OSM réel. Comptage des pixels d’alpha non nul dont le **centre** est hors de la surface d’eau, et non prétention à une précision hydrographique au sous-pixel.

| Tuile | Pixels terrestres opaques avant → après | Pixels d’eau encore non transparents | Calcul masque | Première requête HTTP |
|---|---:|---:|---:|---:|
| 6/33/23 | 219 → 0 | 38821 | 48.35 ms | 593.95 ms |
| 9/264/187 | 82 → 0 | 5036 | 55.86 ms | 3478.17 ms |
| 12/2116/1503 | 40 → 0 | 23352 | 19.65 ms | 2188.73 ms |

RGB identiques dans le rejeu isolé de chaque source ; alpha jamais augmenté. Les trois requêtes finales ont répondu 200. Les mesures froides incluent les services distants et ne mesurent pas les FPS. Réchauffées, trois requêtes par tuile donnent environ 3,4–13,3 ms, avec empreinte PNG stable. Les temps peuvent augmenter avec le réseau et la complexité des géométries.

Tests : terre/mer d’une même tuile, frange antialiasée, trous insulaires, extent non standard, polygones dock/canal, exclusion du glacier, jointure de deux tuiles, île traversant la jointure, alpha source, absence/corruption, cache/single-flight, échec retentable et source transparente. Fixtures réelles Z6/9/12. Les tests synthétiques isolent les erreurs de grille ; les fixtures réelles et les images Android complètent la validation.

Preuves : [coastline-quantitative.json](../../test-results/coastline-seamarks-2026-10-18/coastline-quantitative.json), [warm-cache.json](../../test-results/coastline-seamarks-2026-10-18/warm-cache.json). Le masque n’augmente pas la précision native du raster, ni celle des sondes EMODnet. Les petits détails du littoral OSM peuvent différer de ceux du fond Mapbox.

## F. Couverture marine

Sources réellement interrogées : SHOM WFS Balisage en France, NOAA ENC Direct aux États-Unis, fallback OpenWaters/OSM ; Shortbread pour la géométrie d’eau et les ports. Les résultats bruts, requêtes, normalisations, fusions, conflits et MVT sont conservés dans les fichiers `audit-<zone>.json/.pbf`.

SHOM : WFS 1.0, une classe par requête, `srsName=EPSG:4326`, BBOX longitude/latitude. Capacités réelles archivées dans [shom-capabilities.xml](../../test-results/coastline-seamarks-2026-10-18/shom-capabilities.xml). Comparaison Fréjus avec/sans CRS explicite : même bouée latérale retournée. Maximum observé 81 objets dans une réponse de classe, inférieur au plafond 2 000. Le code échoue explicitement au plafond au lieu de revendiquer une réponse complète.

NOAA : enveloppe et sortie EPSG:4326, pages de 1 000, offset et `exceededTransferLimit` contrôlés ; maximum observé 129 objets par réponse, pas de troncature observée. Au-delà de deux pages, l’adaptateur existant échoue explicitement. Aucun remplacement de ces règles par un résultat partiel silencieux.

Les appels d’audit n’ont enregistré ni échec fournisseur ni 429. Cela ne signifie pas absence d’erreurs pendant toute la session Android : les 503 et annulations 499 sont détaillés dans K. Les réponses peuvent provenir du cache HTTP réel ; l’audit ne force pas un contournement du cache fournisseur.

Les comptes ci-dessous portent sur une **tuile centrale Z14** après sélection spatiale. Les fournisseurs récupèrent une emprise parent plus large ; leurs comptes bruts ne sont donc pas directement comparables. Les 100 m de marge de requête sont plus larges que le buffer MVT : un objet extérieur peut légitimement ne pas être encodé dans cette tuile et être présent dans sa voisine.

| Zone | Normalisés → fusionnés → MVT | Observation |
|---|---|---|
| toulon | 64 → 64 → 57 | Pas de perte d’identité identifiée dans les objets ciblés |
| mandrier | 24 → 24 → 24 | Pas de perte d’identité identifiée dans les objets ciblés |
| giens | 10 → 10 → 10 | Pas de perte d’identité identifiée dans les objets ciblés |
| porquerolles | 16 → 16 → 13 | La balise du bout de jetée est dans la tuile voisine 14/8474/6020 |
| port-cros | 4 → 4 → 4 | Centre déplacé vers quatre bouées jaunes réellement publiées ; centre initial vide conservé comme diagnostic |
| frejus | 7 → 7 → 7 | Pas de perte d’identité identifiée dans les objets ciblés |
| marseille | 5 → 5 → 3 | Pas de perte d’identité identifiée dans les objets ciblés |
| antibes | 9 → 9 → 9 | Pas de perte d’identité identifiée dans les objets ciblés |
| cannes | 16 → 16 → 16 | Pas de perte d’identité identifiée dans les objets ciblés |
| miami | 37 → 34 → 29 | Fusion conservative de doublons multi-échelles ; provenances conservées |
| cape-florida | 8 → 2 → 2 | Doublons NOAA multi-échelles ; phare conservé |

Les contours et chiffres européens restent ceux d’EMODnet ; les chiffres originaux NOAA restent actifs aux États-Unis. Aucune réactivation des sondes SHOM expérimentales, aucun fournisseur exclu réintroduit.

## G. Aides manquantes

Matrice détaillée de **47 lignes** : [object-matrix.csv](../../test-results/coastline-seamarks-2026-10-18/object-matrix.csv). Elle contient 26 objets suivis de bout en bout, 19 objets supplémentaires vérifiés seulement jusqu’au MVT par tests, et deux cas négatifs documentés. Les champs non vérifiés des 19 objets sont laissés vides : ils ne valent pas « absents ».

Les 26 objets ci-dessous ont une source brute identifiée, une normalisation réelle ou rejouée sur cet objet brut, une réponse HTTP MVT NoWave de leur propre tuile, une feature issue de la requête native Mapbox et un symbole localisé sur une capture LGN ouverte. Les tuples de position sont `(longitude, latitude)`. Les valeurs **S/N/M/F/A** signifient fournisseur / normalisation / MVT / Flutter-Mapbox / écran Android. `O/O/O/O/O` ne découle pas de la seule présence MVT.

| Zone | ID fournisseur | Fournisseur · type réel | Position | Zoom | S/N/M/F/A | Cause / correction |
|---|---|---|---|---:|---|---|
| porquerolles | `bcnlat:FR000002455300001` | shom · beacon_lateral | 6.1986891, 43.0040061 | 15.8 | O/O/O/O/O | Support visible à Z15.8 ; masqué par placement/collisions dans la vue Z14, feu superposé visible à sa place |
| mandrier | `bcnlat:FR000002349100001` | shom · beacon_lateral | 5.9217372, 43.0850658 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| mandrier | `bcnlat:FR000002339800001` | shom · beacon_lateral | 5.9250578, 43.0891355 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| mandrier | `bcnlat:FR000012267200003` | shom · beacon_lateral | 5.9314424, 43.0838404 | 14 | O/O/O/O/O | Icône à bandes grises ajoutée ; catégorie et IALA contrôlés |
| mandrier | `lndmrk:FR000009136300003` | shom · lighthouse | 5.9341514, 43.0864693 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| mandrier | `lights:FR000018105400003` | shom · light | 5.9259000, 43.0851167 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| toulon | `bcncar:FR000002390400001` | shom · beacon_cardinal | 5.9235903, 43.1040250 | 12 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| toulon | `lndmrk:FR000005242300001` | shom · lighthouse | 5.9463072, 43.0686526 | 12 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| port-cros | `boyspp:FR000048106000003` | shom · buoy_special_purpose | 6.4061000, 42.9955667 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| port-cros | `boyspp:FR000048106200003` | shom · buoy_special_purpose | 6.4019000, 42.9935578 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| marseille | `bcnlat:FR000002324000001` | shom · beacon_lateral | 5.3106426, 43.2772402 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| marseille | `lights:FR000002250400003` | shom · light | 5.3080863, 43.2744440 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| cannes | `boyspp:FR000065917800003` | shom · buoy_special_purpose | 7.0100000, 43.5403000 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| cannes | `bcnlat:FR000002521400001` | shom · beacon_lateral | 7.0163020, 43.5465002 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| cannes | `lndmrk:FR000008739700003` | shom · lighthouse | 7.0176514, 43.5450685 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| antibes | `bcnlat:FR000002555800001` | shom · beacon_lateral | 7.1301081, 43.5889999 | 15.8 | O/O/O/O/O | Icône à bandes grises ajoutée ; catégorie et IALA contrôlés |
| antibes | `bcnlat:FR000002556200001` | shom · beacon_lateral | 7.1283219, 43.5860010 | 15.8 | O/O/O/O/O | Icône à bandes grises ajoutée ; catégorie et IALA contrôlés |
| miami | `harbour:1:179127` | noaa · beacon_lateral | -80.1585736, 25.7646375 | 16 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| miami | `harbour:1:179125` | noaa · beacon_lateral | -80.1554122, 25.7645503 | 16 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| cape-florida | `harbour:26:62971` | noaa · lighthouse | -80.1558610, 25.6666380 | 14 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| giens | `boylat:FR000052560200003` | shom · buoy_lateral | 6.1106150, 43.0406350 | 16 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| giens | `10893768967` | openwaters · buoy_lateral | 6.1109895, 43.0410809 | 16 | O/O/O/O/O | Objet fallback coloré rendu ; IALA non renseigné et catégorie port/vert ou starboard/rouge discordante avec IALA A, sans inférence géographique |
| giens | `10893768969` | openwaters · buoy_lateral | 6.1111557, 43.0406457 | 16 | O/O/O/O/O | Objet fallback coloré rendu ; IALA non renseigné et catégorie port/vert ou starboard/rouge discordante avec IALA A, sans inférence géographique |
| frejus | `bcnlat:FR000013528100001` | shom · beacon_lateral | 6.7636069, 43.4219667 | 15.8 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| frejus | `bcnlat:FR000014093700003` | shom · beacon_lateral | 6.7636815, 43.4232479 | 15.8 | O/O/O/O/O | Objet rendu dans la vue inspectée |
| frejus | `lndmrk:FR000016155700003` | shom · lighthouse | 6.7631299, 43.4230045 | 15.8 | O/O/O/O/O | Objet rendu dans la vue inspectée |

Détails et attributs complets (couleur, motif, catégorie, forme, IALA, feu associé, provenance, couche, point écran indicatif, source brute, normalisation, MVT) : [object-matrix.json](../../test-results/coastline-seamarks-2026-10-18/object-matrix.json). Les positions écran calculées servent à retrouver les symboles sur les images et ne remplacent pas leur inspection.

Les exemples supplémentaires couvrent notamment deux cardinales fixes, plusieurs balises spéciales et plusieurs feux NOAA/SHOM : [object-matrix-pipeline-only.json](../../test-results/coastline-seamarks-2026-10-18/object-matrix-pipeline-only.json). Leur preuve Android n’a pas été revendiquée.

| Cas négatif | S/N/M/F/A | Cause | Décision |
|---|---|---|---|
| Port-Cros, aucun ID bcnlat dans la BBOX sud auditée | N/N/N/N/N | Réponse officielle de cette classe vide ; BBOX `6.326897263960668,42.93944092245684,6.41724336103932,43.00554543896943` | Aucun objet inventé ; ne signifie pas absence de balises sur toute l’île |
| Fort de la Vigie, `FR000002177600001`, `(6.4003273,42.9989293)` | O/N/N/N/N | Repère `lndmrk`, catégorie 17, fonction 36 ; pas un support de feu de fonction 33 | Ne pas convertir une tour de surveillance en phare |

Preuves négatives : [object-matrix-absence.json](../../test-results/coastline-seamarks-2026-10-18/object-matrix-absence.json). La classe SHOM `bcnsaw` n’est pas publiée par ce service dans les capacités archivées : ne pas inventer une balise fixe d’eaux saines à partir d’une classe inexistante. Les symboles supportés dans l’app ne prouvent pas que leur fournisseur publie chaque famille dans chaque zone.

Diagnostic de Porquerolles : `FR000002455300001` et son feu superposé `FR000005269400001` sont présents aux Z12/13/14 dans les réponses HTTP archivées. Le support est reçu et accepte le filtre natif. La vue complète Z14 place le feu, pas le support. Les expériences de visibilité, recadrage et chevauchement montrent une sensibilité au placement ; certains changements exigent un recalcul après mouvement de caméra. Elles ne permettent pas d’attribuer toute la compétition exclusivement au feu : les bouées proches participent aussi. La vue complète Z15,8 montre le support rouge/blanc et conserve les bouées voisines. Pas de disparition persistante à fort zoom démontrée. Aucun `allowOverlap=true`, changement de tri ou masquage de feu expérimental n’est resté dans l’application finale.

L’écart entre le centre initial de Fréjus et les objets du port était une **emprise de caméra**, corrigée dans les captures par un recentrage sur `(6.7636,43.4225)`. Même principe à Giens : la vue côtière initiale ne ciblait pas le petit groupe de la Madrague ; preuve complémentaire `(6.1109,43.041)` à Z16. Les cinq bouées OpenWaters proches ne deviennent pas toutes visibles simultanément à ce zoom ; trois symboles placés sont constatés, dont une bouée SHOM. La proximité seule n’a pas servi à les fusionner.

## H. Marques latérales

Quatre nouveaux assets 72×72 : `beacon-green-grey`, `beacon-grey-green`, `beacon-red-grey`, `beacon-grey-red`. Le générateur conserve exactement les PNG préexistants, y compris les quatre variantes à bandes blanches.

Le mapping de bandes exige `beacon_lateral`, motif horizontal, ordre des couleurs publié et relation catégorie/couleur cohérente avec le système IALA publié. IALA A : vert tribord / rouge bâbord ; IALA B : vert bâbord / rouge tribord. Aucun système global déduit de la seule localisation, aucune qualification depuis la seule couleur du feu, aucune marque de sommet ajoutée.

Exemples Antibes : `FR000002555800001`, tour fixe vert/gris, tribord A, feu vert lié ; `FR000002556200001`, tour fixe rouge/gris, bâbord A, pas de feu publié associé dans cet objet. Ils traversent réellement toute la chaîne et sont visibles à Z15,8. La première reste visible en overzoom Z17. À Saint-Mandrier, `FR000012267200003` utilise aussi la variante rouge/gris.

Les symboles flottants restent distincts des supports fixes. Les données insuffisantes conservent leur provenance et un rendu prudent. À Giens, deux bouées fallback ont un système IALA vide et une catégorie/couleur discordante avec la règle métropolitaine ; leurs couleurs publiées restent affichées sans leur inventer un système A ou une qualification nouvelle. La qualité de ces attributs source reste une limite.

## I. Autres aides

Seuils existants conservés : bouées Z10 ; phares Z10 ; feux de portée ≥10 M Z11 ; cardinales/dangers isolés fixes qualifiés Z12 ; autres balises Z13 ; petits feux Z14. Les réponses historiquement vides sous Z10 restent un choix de lisibilité, pas un défaut fournisseur corrigé par une baisse globale des seuils.

Contrôles natifs et captures à Z10,12,13,14,15,8 et17. Les MVT seamarks restent natifs jusqu’à Z14 puis overzoom ; l’overzoom ne fabrique aucune nouvelle aide. Les collisions restent actives (`iconAllowOverlap=false`, `iconIgnorePlacement=false`, padding 2 pour les aides fixes). Tri par priorité source puis portée dans les couches fixes ; catégories prioritaires de bouées inchangées. Le [guide Mapbox sur le placement](https://docs.mapbox.com/help/dive-deeper/optimize-map-label-placement/) et la [spécification du tri](https://docs.mapbox.com/style-spec/reference/layers/#symbol-sort-key) complètent les contrôles sur le SDK réel. L’ordre déclaratif ne suffit pas à prouver la visibilité d’un objet : Porquerolles a été testé à l’écran.

La fusion reste conservative : une balise et un feu lié peuvent coexister ; deux aides proches ne sont pas identiques. Test nouveau sur deux vraies latérales grises volontairement colocalisées : les deux identités restent présentes. Les fusions NOAA multi-échelles gardent provenance et conflits ; pas de règle de suppression par distance seule ajoutée.

Isobathes et labels : [final-offshore-z11.9.png](../../test-results/coastline-seamarks-2026-10-18/final-offshore-z11.9.png) / [final-offshore-z12.png](../../test-results/coastline-seamarks-2026-10-18/final-offshore-z12.png), même centre `(5.93,43.06)`. Les courbes apparaissent à Z12 ; la requête native vérifie que les lignes déclarées visibles ont leurs labels. Masquage des contours français généralisés dès Z15 inchangé. Sondes françaises modélisées EMODnet et sondes originales NOAA observées ; pas de précision SHOM fictive.

Épaves, obstructions, rochers et ports : couches et code préexistants préservés, features natives et symboles visibles dans les vues rade, Saint-Mandrier, Frioul et Cape Florida. Le signalement orange, le GPS, le halo, les coordonnées et le badge de zoom sont également présents. Aucun comportement GPS ou signalement modifié pour ces corrections. Les préférences Android de rotation temporairement ajustées pour les captures ont été remises à leurs valeurs initiales : [orientation-restored.json](../../test-results/coastline-seamarks-2026-10-18/orientation-restored.json).

## J. Architecture

| Élément | Changement de cette mission |
|---|---|
| `backend/app/infrastructure/marine/coastline.py` | Masque côtier réel, alpha et cache RAM borné |
| `backend/app/api/routes/map_tiles.py` | Endpoint PNG asynchrone ; source transparente court-circuitée ; réponse masquée et lien d’attribution |
| `backend/app/infrastructure/marine/runtime.py` | Cycle de vie du masque sur le client HTTP existant |
| `backend/app/infrastructure/marine/sources.py` | Métadonnées/attribution du masque OSM |
| `mobile/lib/core/map/marine/marine_map_controller.dart` | Version de cache raster `v=coast-1`, y compris URL portant déjà une query |
| `mobile/lib/features/map/data/fixed_aid_layer.dart` | Quatre variantes grises qualifiées ; mêmes couches et seuils |
| Générateur et assets d’aides fixes | Ajout gris ; images précédentes inchangées |
| Tests/fixtures/documents | Cas littoraux réels, aides officielles, non-régression et provenance |

Endpoints conservés : `/bathymetry/{z}/{x}/{y}.png`, `/seamarks`, `/port-infrastructure`, `/depth-contours`, `/soundings`, `/underwater-hazards`, `/marine-sources`. Pas de nouvel endpoint de profondeur.

Cache : HTTP marin persistant existant partagé ; pas de nouvelle base disque. Les tuiles OSM sont conservées au moins sept jours avec User-Agent identifiant. Masques PNG RAM : maximum 512 entrées / 8 Mio, TTL sept jours, 64 verrous de single-flight. Calcul hors de l’event loop ; échecs non mis en cache comme terre vide. Les PNG publics gardent leur durée d’un jour, avec nouvelle URL mobile pour éviter les anciens PNG non masqués. Les caches, annulations et `no-store` des sondes restent inchangés.

Les sondes volatiles, le raster BOTTOM, la texture d’eau et les aides TOP gardent leurs installations idempotentes. Le test réel de rechargement ci-dessous a doublé volontairement les appels d’installation sans doublonner les sources/couches.

## K. Validation Android

LGN LX1 `AV5PJV6328H03108`, Android 15 / API35, arm64, USB. Reverse `tcp:8004 → tcp:8004`. Backend local `http://127.0.0.1:8004`, `/health` et `/openapi.json` contrôlés. Aucun déploiement distant, aucune désinstallation ni suppression des données de l’app.

Construction effective :

```bash
cd mobile
/home/palms/flutter/bin/flutter build apk --debug --no-pub \
  --dart-define-from-file=.env.json \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/ \
  '--dart-define=BATHYMETRY_TILES_URL=http://127.0.0.1:8004/api/v1/map/bathymetry/{z}/{x}/{y}.png'
adb -s AV5PJV6328H03108 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Build réussi en 9 s, installation réussie ; configuration `.env.json` non divulguée. Le SHA-256 de l’APK locale est identique à celui du `base.apk` effectivement installé :

`730b888db4c2f97fb53b3f5e04957effd78f773ec14fc734311b24edf79fc0a4`

Preuves : [apk-build.log](../../test-results/coastline-seamarks-2026-10-18/apk-build.log), [install.log](../../test-results/coastline-seamarks-2026-10-18/install.log), [apk-installed.json](../../test-results/coastline-seamarks-2026-10-18/apk-installed.json). La configuration native après rechargement contient le raster local `...png?v=coast-1` et les endpoints MVT locaux attendus, sans ancienne URL WMS dans la source mobile. Le backend audit a effectivement reçu le User-Agent Mapbox Android LGN ; pas seulement des requêtes curl.

Les scripts de validation passent l’app au premier plan puis vérifient centre/zoom natifs, absence de panneau d’erreur et activité Android réellement active avant capture. Les résultats natifs sont un échantillon plafonné à 90 features par interrogation groupée : leurs comptes ne sont pas une mesure de complétude de toutes les aides du secteur.

| Vue ouverte sur LGN | Centre longitude, latitude | Zoom | Constat principal |
|---|---|---:|---|
| [final-rade-z10.png](../../test-results/coastline-seamarks-2026-10-18/final-rade-z10.png) | 5.93, 43.106 | 10 | Bouées à leur seuil existant |
| [final-rade-z12.png](../../test-results/coastline-seamarks-2026-10-18/final-rade-z12.png) | 5.93, 43.106 | 12 | Bouées, cardinale fixe, phares, dangers et signalement |
| [final-mandrier-z13.png](../../test-results/coastline-seamarks-2026-10-18/final-mandrier-z13.png) | 5.928, 43.085 | 13 | Seuil des balises locales ; dangers et phare |
| [final-mandrier-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-mandrier-z14.png) | 5.928, 43.085 | 14 | Balises blanches/grises et feu local |
| [final-giens-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-giens-z14.png) | 6.12, 43.04 | 14 | Vue côtière de repérage ; ne prouve pas le groupe de bouées |
| [final-giens-aids-z16.png](../../test-results/coastline-seamarks-2026-10-18/final-giens-aids-z16.png) | 6.1109, 43.041 | 16 | Groupe réel de la Madrague, 3 bouées placées |
| [final-porquerolles-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-porquerolles-z14.png) | 6.2, 43.005 | 14 | Bouées et feu placés ; balise masquée par placement |
| [final-porquerolles-z15.8.png](../../test-results/coastline-seamarks-2026-10-18/final-porquerolles-z15.8.png) | 6.1986891, 43.0040061 | 15.8 | Support rouge/blanc visible, bouées préservées |
| [final-port-cros-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-port-cros-z14.png) | 6.404, 42.995 | 14 | Deux bouées jaunes dans le cadrage sud |
| [final-frejus-recentered-z15.8.png](../../test-results/coastline-seamarks-2026-10-18/final-frejus-recentered-z15.8.png) | 6.7636, 43.4225 | 15.8 | Deux balises fixes et phare de Saint-Raphaël |
| [final-marseille-aids-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-marseille-aids-z14.png) | 5.308, 43.278 | 14 | Latérale de Frioul, feu rouge et épaves |
| [final-cannes-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-cannes-z14.png) | 7.016, 43.545 | 14 | Latérale verte, phare et bouée spéciale |
| [final-antibes-z15.8.png](../../test-results/coastline-seamarks-2026-10-18/final-antibes-z15.8.png) | 7.129, 43.588 | 15.8 | Deux balises à bandes grises |
| [final-antibes-z17.png](../../test-results/coastline-seamarks-2026-10-18/final-antibes-z17.png) | 7.1301081, 43.5889999 | 17 | Balise vert/gris conservée en overzoom |
| [final-miami-z16.png](../../test-results/coastline-seamarks-2026-10-18/final-miami-z16.png) | -80.157, 25.763 | 16 | Deux latérales vertes NOAA bâbord IALA B et sondes |
| [final-cape-florida-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-cape-florida-z14.png) | -80.155, 25.67 | 14 | Phare NOAA et hydrographie américaine |
| [final-vauban-z14.png](../../test-results/coastline-seamarks-2026-10-18/final-vauban-z14.png) | 5.925, 43.1145 | 14 | Quais, aides et dangers ; bleu limité à l’eau |
| [final-vauban-z16.png](../../test-results/coastline-seamarks-2026-10-18/final-vauban-z16.png) | 5.925, 43.1145 | 16 | Détails portuaires ; terre et bassins cohérents |

Rechargement réel du style, puis double installation des composants raster/hydro/aides : [reload-proof.json](../../test-results/coastline-seamarks-2026-10-18/reload-proof.json). **9 sources et 26 couches natives uniques**, quatre nouvelles images présentes. [final-after-reload-z12.png](../../test-results/coastline-seamarks-2026-10-18/final-after-reload-z12.png) ouverte : raster, courbes, labels, sondes, aides et signalement retrouvés.

GPS : appui physique sur le bouton existant, arrivée Z15,5 avec suivi désactivé ; glissement réel de la carte puis caméra stable, sans recentrage intempestif. Preuves : [gps-proof.json](../../test-results/coastline-seamarks-2026-10-18/gps-proof.json), [final-gps-arrival-z15.5.png](../../test-results/coastline-seamarks-2026-10-18/final-gps-arrival-z15.5.png), [final-gps-pan-free.png](../../test-results/coastline-seamarks-2026-10-18/final-gps-pan-free.png). Longitude caméra passée de `5.9340359` à `5.9352781`, puis stable ; latitude `43.0851626`, zoom 15,5. Pas de changement du code GPS ou des signalements.

Une capture de Porquerolles Z14 était recouverte par le volet système malgré une activité NoWave encore déclarée au premier plan. Elle a été écartée et conservée comme tentative ; la capture liée ici a été refaite puis ouverte. Le dernier script contrôle aussi la fenêtre `mCurrentFocus` Android. L’inspection visuelle de chaque image retenue complète ces garde-fous.

Les essais non valides sont conservés : certaines premières captures ont rencontré une autre app au premier plan ou le panneau réseau ; elles ne sont pas retenues comme preuve de rendu. Une tentative Toulon étiquetée Z14 mais réellement Z15 a été archivée puis recapturée. Les images finales retenues figurent dans `final-scenes.jsonl`, avec centre et zoom natifs vérifiés. Les images de diagnostic avec couches désactivées ne sont pas des captures finales.

Un plantage natif Flutter a eu lieu pendant une expérimentation de zone d’identifiants du débogueur VM ; sa cause précise n’est pas établie. Journal conservé. La collecte suivante emploie la zone standard et des sessions courtes, sans répétition de ce plantage dans la séquence finale. Cela ne remplace pas un essai de stabilité en release.

Les erreurs réseau de toute la session sont conservées, pas effacées des preuves. Les échecs PNG retournent 503 et les annulations de sondes 499 ; plusieurs accès ont ensuite réussi. Les séquences finales utilisées pour les captures ont été contrôlées avec l’app au premier plan et sans panneau d’erreur. Relevé à `2026-10-18T15:22:39.671916+00:00` : **1084 requêtes LGN**, dont **992 réponses 200, 63 réponses 503 et 29 annulations 499**. Les 503 comprennent 43 PNG, 16 sondes et 4 contours ; seamarks, ports et dangers n’ont pas répondu 503 dans ce relevé. Preuve : [device-request-summary.json](../../test-results/coastline-seamarks-2026-10-18/device-request-summary.json). Il ne s’agit donc pas d’une disponibilité 100 %.

## L. Tests

Commandes exécutées dans les environnements fonctionnels du projet :

```bash
PYTHONMALLOC=malloc /tmp/nowave-hydro-corrective/venv312/bin/python -m pytest -q
.venv/bin/ruff check backend
cd mobile
/home/palms/flutter/bin/dart format --output=none --set-exit-if-changed lib test
/home/palms/flutter/bin/flutter analyze --no-pub
/home/palms/flutter/bin/flutter test --no-pub
```

| Vérification | Résultat |
|---|---|
| Backend complet | **864 réussis**, aucun échec ni test sauté ; 1 avertissement Starlette/httpx préexistant |
| Ruff backend | Tous les contrôles passent |
| Dart format | 167 fichiers, aucun changement requis |
| Flutter analyze | Aucun problème |
| Flutter complet | **491 réussis**, aucun échec ni test sauté |
| Git diff check | Propre |

Les 825 tests backend et 490 tests Flutter historiques sont conservés. Les nouvelles régressions couvrent le masque et son cache, 22 vrais objets officiels à travers normalisation/fusion/MVT, deux identités proches, mapping gris/IALA, URL versionnée avec query et idempotence des assets. Les échecs intermédiaires sont restés archivés ; ils ont conduit à corriger l’alignement de demi-échantillon et l’attente de la liste des sources. Aucun test supprimé pour obtenir ces résultats.

Journaux : [pytest-review2-final.log](../../test-results/coastline-seamarks-2026-10-18/pytest-review2-final.log), [ruff.log](../../test-results/coastline-seamarks-2026-10-18/ruff.log), [dart-format.log](../../test-results/coastline-seamarks-2026-10-18/dart-format.log), [flutter-analyze.log](../../test-results/coastline-seamarks-2026-10-18/flutter-analyze.log), [flutter-tests.log](../../test-results/coastline-seamarks-2026-10-18/flutter-tests.log).

## M. Revue 1

Première passe par le même agent sur le delta par rapport à la copie initiale, et non sur un diff Git qui mélange les missions. Contrôle du masque, des erreurs, caches, frontière, données brutes et règles d’icônes.

Problèmes détectés puis traités : alignement sous-pixel du rasteriseur ; attente de sources du test API à compléter pour l’attribution ; absence de variantes grises réellement publiées ; coût inutile du masque pour un PNG déjà transparent. Les anciens assets ont été comparés par empreinte et restent identiques. Aucun changement aux adaptateurs de profondeurs ou à la fusion antérieure.

La validation a également rejeté les images hors premier plan et une caméra au mauvais zoom. Les captures correspondantes ont été conservées comme tentatives, puis remplacées dans les preuves retenues. Les limites de découpage entre marge fournisseur et buffer MVT ont été distinguées d’une disparition d’objet.

## N. Revue 2

Seconde passe séparée du **même agent**, repartie des exigences et des preuves réelles. Ce ne sont pas deux avis indépendants.

Relecture des images finales Z6/Z9, Hyères, Fréjus, ports et îles ; contrôle des images Z14/Z16 vraiment côtières ; inspection des matrices et des coordonnées pour éviter de confondre présence native et symbole visible. Vérification des 26 chaînes complètes, des 19 preuves limitées au pipeline et des deux cas négatifs.

Porquerolles a été repris jusqu’au MVT réel et à la requête source native : le support n’était pas perdu. Le placement varie avec le zoom ; Z15,8 rend la balise. Les diagnostics n’ont pas justifié une modification globale des collisions ou des seuils. Les réglages expérimentaux ont été réinitialisés par réinstallation des couches depuis le code de l’APK, puis rechargement du style. Leur état final est également relevé nativement : [final-style-properties.json](../../test-results/coastline-seamarks-2026-10-18/final-style-properties.json), tous les overlaps et ignore-placement des aides à `false`.

Le style rechargé est sans doublon, les nouvelles images existent, les labels correspondent aux courbes visibles, les sondes restent volatiles, et le bouton GPS conserve le recentrage unique Z15,5 puis le déplacement libre. Les suites complètes ont été relancées après cette seconde passe : **864 backend réussis en 4,38 s et 491 Flutter réussis** ; Ruff, format et analyse relancés passent également. Journaux : [pytest-review2-final.log](../../test-results/coastline-seamarks-2026-10-18/pytest-review2-final.log), [flutter-review2.log](../../test-results/coastline-seamarks-2026-10-18/flutter-review2.log), [ruff-review2-final.log](../../test-results/coastline-seamarks-2026-10-18/ruff-review2-final.log), [dart-format-review2.log](../../test-results/coastline-seamarks-2026-10-18/dart-format-review2.log), [flutter-analyze-review2.log](../../test-results/coastline-seamarks-2026-10-18/flutter-analyze-review2.log). Les empreintes de l’APK ont été contrôlées. Cette seconde passe a aussi corrigé une course de cache : une entrée expirée peut être évincée pendant l’attente HTTP de son recalcul. Le remplacement utilise désormais l’entrée encore présente, si elle existe ; un test concurrent à cache plein vérifie l’absence de KeyError et la comptabilité mémoire. Le backend final a été rechargé avec le même environnement puis ses endpoints contrôlés : [backend-final-smoke.json](../../test-results/coastline-seamarks-2026-10-18/backend-final-smoke.json). Les PNG Z6/Z9/Z12 répondent 200 et gardent les mêmes SHA-256 après ce correctif de concurrence, sans changement de rendu. Les limites de géométrie, de collision, de fournisseur et de mesure de performance sont conservées dans P.

## O. État Git final

Branche et HEAD inchangés ; index non modifié. Aucun fichier initial manquant. Les 705 fichiers du point de départ ont été comparés à leurs empreintes : **13 fichiers existants enrichis par cette mission**, les 692 autres identiques. Les changements propres sont superposés au travail hydrographique antérieur ; ils ne le remplacent pas. Les quatre PNG à bandes blanches et les archives de sondes SHOM sont inchangés, ainsi que `.env.json`.

État complet du workspace : **22 fichiers suivis modifiés, 45 non suivis** ; 715 fichiers suivis ou non ignorés. Ajouts propres à cette mission : **10 fichiers**, rapport compris. Ce total diffère légitimement de l’état historique.

Fichiers existants enrichis par cette mission :

- `backend/app/api/routes/map_tiles.py`
- `backend/app/infrastructure/marine/runtime.py`
- `backend/app/infrastructure/marine/sources.py`
- `backend/tests/api/test_map_tiles.py`
- `backend/tests/api/test_marine_tiles.py`
- `backend/tests/fixtures/marine/README.md`
- `docs/architecture/marine-sources.md`
- `mobile/assets/icons/fixed-aids/README.md`
- `mobile/lib/core/map/marine/marine_map_controller.dart`
- `mobile/lib/features/map/data/fixed_aid_layer.dart`
- `mobile/test/core/map/marine/marine_map_controller_test.dart`
- `mobile/test/features/map/data/fixed_aid_layer_test.dart`
- `mobile/tool/make_fixed_aid_icons.py`

Fichiers ajoutés par cette mission :

- `backend/app/infrastructure/marine/coastline.py`
- `backend/tests/fixtures/marine/coastline-real.json`
- `backend/tests/fixtures/marine/seamarks-coast-audit.json`
- `backend/tests/unit/test_coastline.py`
- `backend/tests/unit/test_seamark_coast_audit.py`
- `docs/test-reports/marine-coastline-seamarks-2026-10-18.md`
- `mobile/assets/icons/fixed-aids/beacon-green-grey.png`
- `mobile/assets/icons/fixed-aids/beacon-grey-green.png`
- `mobile/assets/icons/fixed-aids/beacon-grey-red.png`
- `mobile/assets/icons/fixed-aids/beacon-red-grey.png`

Les preuves `test-results/coastline-seamarks-2026-10-18/` sont ignorées par Git et conservées localement ; elles ne sont pas comptées comme nouveaux fichiers Git. Le manifeste final, l’état complet et le delta propre à la mission sont archivés avec les preuves et dans la copie externe. Relevé final : [final-git-audit.json](../../test-results/coastline-seamarks-2026-10-18/final-git-audit.json), [delta propre](../../test-results/coastline-seamarks-2026-10-18/task-delta.patch). `git diff --check` est relancé après rédaction du rapport. Aucun commit, push ou PR.

## P. Limitations

- Le constat « pas de bleu perceptible sur terre » porte sur les vues examinées. Les tuiles quantitatives prouvent zéro centre de pixel terrestre opaque selon **la géométrie OSM employée**, pas l’identité absolue d’OSM avec Mapbox, le SHOM ou une ligne de marée. Les géométries de faible zoom sont généralisées ; le raster s’overzoome après son niveau natif.
- Le coût froid dépend des services distants ; le masque ajoute une dépendance géométrique quand le raster contient de la couleur. En cas d’échec, 503 au lieu d’une image qui déborderait. Les temps serveur ne sont pas des mesures FPS. Aucun benchmark GPU/release exhaustif.
- Un symbole placé par Mapbox peut être masqué dans un autre cadrage par des aides voisines, un feu, une sonde, un danger, le GPS ou l’interface. À Porquerolles Z14 la balise n’est pas visible dans la vue retenue ; elle l’est à Z15,8. Les cinq bouées très proches de Giens ne sont pas toutes séparables à Z16. Aucun chevauchement forcé ni fusion par proximité pour rendre artificiellement tous les objets.
- Les catégories manquantes ou contradictoires du fallback restent une limite des données. Deux bouées de Giens ont notamment une catégorie/couleur incompatible avec la règle IALA A mais aucun système publié ; le rendu n’a pas inventé d’IALA ou de topmark pour elles.
- Une réponse vide dans la BBOX sud de Port-Cros ne signifie pas absence sur toute l’île. La tour de surveillance de la Vigie n’est pas un phare. Une classe non publiée par le service ne prouve pas l’inexistence de toutes les aides de cette famille sur le terrain.
- L’échantillon ne certifie pas toutes les aides critiques, toutes les côtes ou toutes les pannes possibles. Les erreurs réseau observées et l’incident du débogueur sont archivés. L’APK validée est debug ; aucune recette distante ni release effectuée.
- Les chiffres EMODnet restent modélisés avec leur précision native. La couleur bathymétrique ne fournit aucun chiffre nouveau. Les règles de masquage des contours français après Z15, les sources numériques Europe/USA, le GPS et les signalements restent ceux des missions précédentes.

Travail arrêté après validation locale et rapport, sans commit, push ou PR.
