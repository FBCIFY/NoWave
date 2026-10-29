# NoWave — ports à Z6 et rendu côtier — 19 octobre 2026

Travail local sur `feature/marine-bathymetry`, dépôt `FBCIFY/NoWave`, HEAD initial
`11667a069aad0e485c99281e812cb9c68cb7a92e`. Aucun fichier suivi modifié au départ.
Les seuls éléments non suivis préexistants étaient la photographie
`3d-rendering-planet-earth.jpg` et `backend/app/infrastructure/marine/data/shom-surveys/`.
Ils sont préservés, de même que `.env.json`. Aucun commit, push, changement de
branche ou PR ; aucune intervention distante.

## Architecture et données de ports

Pipeline conservé : provider → entité marine WGS84 → service de tuiles/cache →
encodeur MVT → source vectorielle Flutter → symboles Mapbox Standard/globe.
Ajout de la famille publique `/api/v1/map/harbours/{z}/{x}/{y}.pbf`, couche MVT
`harbour`. Les infrastructures détaillées restent dans `port-infrastructure`.

IGN BD TOPO fournit ici les constructions linéaires `nature=Quai` ; NOAA ENC
les ouvrages et aides ; Shortbread les surfaces/lignes d'ouvrages. Ces objets
ne deviennent pas des ports. Le provider Open Waters déjà intégré publie aussi
des objets explicitement `type=harbour`, avec des points représentatifs, noms,
catégories et identités. Ce sous-ensemble OSM est maintenant utilisé.

Les ports sont absents des tuiles Open Waters Z6/Z7, présents dès Z8. Le backend
regroupe donc **16 tuiles Z8 par tuile Z6, 4 par tuile Z7**, à la demande ; Z8–14
emploie la précision native. Aucun catalogue mondial n'est embarqué. MarineHTTP
conserve ses limites de connexions, taille, cache persistant et délais ; cache
amont des ports 24 h, cache MVT partagé borné 512 entrées/32 Mio, normalement 5 min.
Une sous-tuile indisponible produit une erreur retentable, jamais une région
partiellement chargée déclarée vide avec succès.

Seuls les **points qualifiés par le fournisseur** sont retenus. Les doubles
représentations surface/point ne produisent qu'un symbole. Le fournisseur utilise
un point sur la surface pour les polygones ; NoWave ne calcule aucun centroïde de
quai ou de polygone découpé. Coordonnées et tuile d'origine sont conservées via la
géométrie et `source_tile`, avec `position_method=provider-point`. Les coordonnées
restent soumises à la quantification MVT amont.

La déduplication utilise l'identifiant MVT du fournisseur, qui distingue les
espaces node/way/relation, et conserve l'OSM ID brut et les provenances. Un même
numéro OSM seul ne prouve pas une identité. Des ports voisins ou homonymes ne sont
pas fusionnés arbitrairement. Aucun second provider de lieux portuaires n'est
ajouté ; les identités partagées sont prévues et testées pour la fusion.

La catégorie `marina` est utilisée uniquement lorsqu'elle est publiée. Toutes
les autres catégories gardent une ancre générique et l'attribut source original.
Aucune catégorie « petit port » ou « abri » n'est inventée. Le catalogue reste
communautaire, non exhaustif ; des ports lacustres/fluviaux qualifiés existent aussi.

Sources et licences : [Open Waters](https://github.com/openwatersio/seamap),
[données et attribution](https://openwaters.io/charts/seamap),
[OSM marina](https://wiki.openstreetmap.org/wiki/Tag:leisure%3Dmarina).
Tuiles Open Waters CC BY 4.0, données OSM sous ODbL ; crédits déjà présents dans
l'application et nouvelle entrée dans `marine-sources`. Aucun code ni pictogramme
Open Waters n'a été copié.

## Symboles, seuil et collisions

`HarbourLayer.harbourMinZoom = 6.0`, minzoom de source 6, minZoom de couche 6,
maxzoom de source 14 et conservation des symboles en overzoom. Ancres originales
NoWave dessinées par Canvas, fond transparent, PNG 72×72 à densité 3. Dessin
original dédié à CC0 1.0, comme les symboles fixes NoWave ; une petite marque
annulaire distingue les marinas qualifiées. Pas de nouvelle dépendance mobile.

Interpolation linéaire : Z6=0,62 ; Z8=0,72 ; Z10=0,85 ; Z12=1 ; Z14=1,08 ;
Z18=1,12. Soit environ 15 à 27 pixels logiques, taille plafonnée. Collisions
actives, marge 3, ports nommés prioritaires puis génériques avant marinas,
ordre d'identité stable à priorité égale. Aucun filtre de densité qui viderait
un niveau de zoom. Les aides à la navigation restent prioritaires dans le slot
supérieur ; la nouvelle couche ne modifie ni leurs seuils ni leurs expressions.
Les installations répétées/concurrentes et le rechargement du style sont testés.

## Validation effective sur Android

LGN LX1 `AV5PJV6328H03108`. APK debug installée avec `adb install -r`, sans effacer
les données. Backend principal distant issu du `.env.json` existant ; API marine
locale `http://127.0.0.1:8004/`, via `adb reverse tcp:8004 tcp:8004`.
Backend local rechargé avec son environnement existant, sans divulguer ses valeurs.
Aucun proxy HTTP démarré ou utilisé, aucun déploiement distant.

Les 30 captures finales ont été ouvertes sous forme de planche, ainsi que les
comparaisons côtières en pleine résolution. Les requêtes **queryRenderedFeatures**
du SDK donnent les résultats suivants, zoom effectif relu après déplacement :

| Vue centrée sur | Z5,9 | Z6 | Z8 | Z10 | Z12 | Z14 |
|---|---:|---:|---:|---:|---:|---:|
| Toulon / rade | 0 | 31 | 13 | 2 | 1 | 0 |
| Marseille | 0 | 27 | 13 | 4 | 10 | 7 |
| Saint-Mandrier | 0 | 31 | 13 | 2 | 1 | 1 |
| Porquerolles | 0 | 32 | 14 | 3 | 1 | 1 |
| Miami | 0 | 38 | 10 | 7 | 9 | 9 |

Ce sont des symboles dans la **vue**, pas le nombre de ports de chaque commune.
À Z6 la vue est régionale. Le cadrage Toulon Z14 est centré dans la rade et ne
contient pas de port retenu visible ; ce n'est pas un maxZoom de couche. Aucun
identifiant répété dans les résultats des 30 requêtes. Les tuiles HTTP Z5 sont
vides, celles Z6 contiennent des ports réels (350 dans la tuile régionale à l'est
de Toulon, 234 dans celle de Miami). Toutes les 30 requêtes HTTP de la matrice
retournent 200, avec contenu et provenance contrôlés.

Preuves : `test-results/cartography-z6-2026-10-19/` :
`native-harbour-queries.json`, `native-sources.json`, `harbour-http-matrix.json`,
`final-contact.jpg`, `final-*.png`, `before-*.png`, `after-*.png`.

Les contrôles complémentaires du GPS et de session ont réussi : recentrage
ponctuel à Z15,5, déplacement manuel conservé ensuite à Z12, profil distant
retourné sous forme `UserProfile` sans extraction du jeton. Le globe et le
passage nuageux Z5,3 ont aussi été capturés. À la reprise de la session, la
redirection USB avait disparu ; elle a été rétablie puis les captures rapprochées
répétées avec le backend accessible (`connected-*.png`,
`connected-device-checks.json`). Les captures précédentes sont conservées.

## Carrés côtiers et qualité graphique

Le test Android avec le raster temporairement masqué confirme que le cyan est
le fond Mapbox visible dans les trous de couverture du raster. Le PNG EMODnet
inspecté à Toulon possède un alpha binaire 0/255 ; le découpage grossier de cette
couverture est fortement agrandi au-delà du Z14 natif. Les tuiles voisines et le
masque côtier OSM existant ont été examinés. Ce n'est pas une texture de vagues.

Traitement ajouté : fondu **uniquement vers l'intérieur** de l'alpha,
GaussianBlur de rayon 0,8 pixel puis minimum avec l'alpha initial. Un pixel
sans données garde alpha=0 ; les RGB sont inchangés par ce traitement. Les
pixels intérieurs restent opaques. La requête WMS reçoit une marge de 3 pixels,
262×262 au même pas géographique, puis est recadrée en 256×256. Cette marge
évite de confondre une frontière de tuile avec une frontière de couverture.
Le test de mosaïque confirme le raccord identique de deux tuiles contiguës.
La palette, la LUT et l'algorithme hydrographique sont conservés. Le cache client
passe à `v=coast-feather-2` pour charger effectivement ce rendu.

Le fondu atténue la transition brutale, **sans supprimer l'emprise inconnue**.
Les zones cyan restent perceptibles, notamment à Z16–17. Le raster est déjà
échantillonné en linéaire ; le forcer à une résolution supérieure n'ajouterait
aucune mesure. Pas de flou global, pas de déplacement de géométrie et pas de
changement des chiffres. Le gain constaté est local aux bords et aux symboles,
non une augmentation de résolution de la donnée bathymétrique.

## Infrastructures et repères fixes

Les quais linéaires IGN/ENC étaient conservés dans `port_infrastructure` mais
sans couche de rendu correspondante. Ils sont maintenant aussi encodés dans
`pier_lines` avec `kind=quay`, et dessinés finement, avec extrémités/jonctions
arrondies à partir de Z13. Géométrie strictement identique, fusion multi-source
existante conservée. Cache `v=quays-2`. Les bassins, digues, pontons et surfaces
existants gardent leurs styles et seuils.

Exemples vérifiés : Porquerolles `shom:bcnlat:FR000002455300001` est une balise
latérale rouge/blanc, bâbord, IALA A, support pile ; ce n'est pas une bouée.
Des objets distincts `shom:lights:*` sont des feux et restent des feux. À Miami,
les balises Fishermans Channel sont publiées IALA B ; leur qualification demeure.
Les icônes de balises déjà correctement sélectionnées restent inchangées.

Seuls les cinq dessins de feux isolés passent à une petite étoile à quatre rayons,
72×72 à densité 6, **toujours 12 pixels logiques**, pour mieux distinguer un feu
d'un point neutre. Forme, couleur, provenance et règles de sélection restent
séparées ; aucune catégorie n'est déduite d'une seule couleur. Les icônes des
bouées et phares sont inchangées. Artwork original NoWave CC0, générateur et
README mis à jour.

## Non-régression et tests

**Profondeurs inchangées** : sources, normalisation, fusion hydrographique,
MVT, valeurs, unités, datums, densité, labels, tailles et seuils n'ont pas été
modifiés. Les six réponses MVT de contrôle (contours, sondes, dangers ; Toulon
et Miami) sont identiques octet par octet avant/après, avec SHA-256 enregistrés.
Les fichiers du globe, de la traversée Z5, du GPS, des bouées et des reports
restent inchangés. Les empreintes de `.env.json`, photo, archives SHOM et des
fichiers protégés sont vérifiées dans `preservation-final.json`.

Commandes exécutées :

```bash
.venv/bin/python -m pytest -q
.venv/bin/ruff check backend
cd mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub \
  --dart-define=API_BASE_URL=https://api.no-wave.fr/ \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/ \
  test/features/map/data/api_sources_test.dart \
  test/features/map/data/harbour_layer_test.dart
flutter build apk --debug --no-pub --dart-define-from-file=.env.json \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/
```

Résultats : **879 tests backend API/unitaires**, **535 tests Flutter**, **5 tests
Flutter avec les deux API** réussis. Formatage conforme, analyse sans problème,
Ruff et `git diff --check` sans erreur. APK debug construite. Un avertissement
Starlette/httpx côté tests et un avis de migration Kotlin dans le build, sans
échec de compilation. `BATHYMETRY_TILES_URL` n'a pas été recréée : cette ancienne
variable n'est plus utilisée ; la base marine configure déjà le raster local.

La commande supplémentaire `.venv/bin/python -m pytest backend/tests -q`
a exécuté la suite étendue : 877 réussites au moment de cette passe et **275
erreurs de préparation PostgreSQL**, toutes dues à `NOWAVE_TEST_ADMIN_URL`
absente. Docker Desktop Linux n'est pas démarré et aucun PostgreSQL de test
n'est accessible. Les deux nouveaux tests ajoutés ensuite passent dans les 879.
La validation complète avec base de données **n'est donc pas acquise** ; aucune
base existante n'a été modifiée pour contourner ce blocage.

## Deux revues

1. Revue technique du diff complet et des nouveaux fichiers : correction d'un
   risque de collision entre identifiants OSM numériques en utilisant l'identité
   MVT ; isolation des pannes de la source de ports pour conserver les autres
   couches ; sérialisation des installations et tests de reload ; tests du
   refus des couvertures partielles et du cache ; protection alpha/RGB et
   raccords ; revue des routes et de l'absence de jeton utilisateur vers l'amont.
2. Revue fonctionnelle/visuelle : 30 requêtes natives et captures, seuil Z5,9/Z6
   effectivement observé, aucune identité dupliquée, cohabitation avec aides et
   profondeurs, comparaison Toulon/Porquerolles/Marseille/Mandrier/Miami. Le gain
   de lissage reste modeste et localisé ; aucune revendication d'une bathymétrie
   plus précise. Les limites de couverture amont et des tests PostgreSQL sont
   explicites.

Les nouveaux fichiers sont `harbours.py`, `test_harbours.py`,
`harbour_layer.dart`, `harbour_layer_test.dart` et ce rapport. Les fichiers
modifiés concernent routes/domaine/service/runtime/MVT/crédits, rendu alpha,
rendu portuaire/feux/installation Flutter, cinq PNG de feux et leurs tests.
Aucune suppression. La liste exhaustive et le diff sont dans les preuves Git.

État final : 26 fichiers suivis modifiés et 5 nouveaux fichiers de travail,
auxquels s'ajoutent les deux éléments personnels non suivis préexistants.
Rien n'est indexé ; HEAD reste `11667a069aad0e485c99281e812cb9c68cb7a92e`
sur `feature/marine-bathymetry`. Le réglage temporaire de maintien en veille
USB du téléphone a été restauré à sa valeur initiale `0`, puis relu pour
confirmation (`stay-awake-final.txt`). La redirection ADB du port 8004 est
conservée pour permettre l'accès de l'application au backend local.

**Ports à Z6 validés sur Android ; profondeurs inchangées ; globe préservé.
Aucun commit. Aucun push. Aucune PR.**
