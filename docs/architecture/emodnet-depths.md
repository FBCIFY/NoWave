# Profondeurs modélisées EMODnet 2024 — contrat MVP

Implémentation locale du 18 octobre 2026, avec correction de l'annulation HTTP
le 31 octobre 2026 ([PR #142](https://github.com/FBCIFY/NoWave/pull/142)).
Cette annexe précise le fournisseur des chiffres de profondeur et le contrat
backend MVT conservé. Depuis NW-220, le mobile charge des snapshots GeoJSON et
alimente des sources Mapbox GeoJSON. Les anciens paramètres de source vectorielle
sont identifiés comme historiques ci-dessous ; les règles actuelles de chargement,
de zoom et de conservation sont décrites dans
[Seuils et conservation maritimes](marine-zoom-persistence.md).

## Flux et sélection

### Route MVT conservée

Le backend expose toujours ce contrat pour les clients, outils et tests MVT.
La source Flutter vectorielle du schéma correspond au client initial du 18 octobre.

```text
Ancien client Flutter / Mapbox VectorSource (Z12, max source Z16)
  → GET /api/v1/map/soundings/{z}/{x}/{y}.pbf
  → MarineTileService (cache final RAM partagé, requêtes identiques sérialisées)
  → EmodnetDepthProvider (client HTTP dédié sans cache disque)
  → ERDDAP griddap bathymetry_dtm_2024.csv, sélection bornée par indices
  → vérification stricte du CSV, cellules marines normalisées en mémoire
  → encode_hydro_tile, couche MVT « sounding », extent 4096
  → labels numériques depth_label
```

### Pipeline mobile actuel NW-220

[`MarineViewport`](../../mobile/lib/features/map/data/marine_viewport.dart)
demande explicitement
`GET /api/v1/map/marine-features/soundings/{z}/{x}/{y}.geojson`.
Cette [route](../../backend/app/api/routes/map_tiles.py) réutilise
`MarineTileService` avec `geojson=True`, la même sélection de fournisseurs et le
même adaptateur ERDDAP. L'[encodeur de snapshots](../../backend/app/infrastructure/marine/viewport_encoding.py)
renvoie une `FeatureCollection` WGS84 avec les propriétés et labels de profondeur,
sans passer par la quantification MVT.

Le mobile conserve les snapshots et publie leur contenu dans la source
`nowave-soundings` de
[`HydrographyLayer`](../../mobile/lib/features/map/data/hydrography_layer.dart),
désormais une `GeoJsonSource` avec `tolerance=0` et `maxzoom=18`.
Les sondes sont préparées dès Z12 et affichées dès Z13. Leur résolution demandée
est plafonnée à Z16 et peut être réduite selon le budget de la vue ; le
`maxzoom=18` du découpage interne GeoJSON ne crée pas de données fournisseur plus
fines. Les règles de relève, de réponses partielles et de réinstallation du style
sont détaillées dans [NW-220](marine-zoom-persistence.md#courbes-et-sondes).

`MarineTileService.select` réserve les chiffres européens à `emodnet-dtm-2024`.
Depuis la correction du 18 octobre et le choix utilisateur, les sondes ENC NOAA
sont rétablies dans leur couverture, hors EMODnet. Le
[`NoaaSoundingProvider` actuel](../../backend/app/infrastructure/marine/hydro_providers.py)
permet leur préparation dès Z12 ; l'encodeur GeoJSON utilise une grille de
sélection d'au moins Z14, distincte du seuil de chargement. Cette sélection est
géographique : aucun repli NOAA lors d'une panne EMODnet, et aucun
mélange avec SHOM, Seascape ou DCDB. Le runtime remplace seulement l'instance du
fournisseur de sondes SHOM par EMODnet. Le code, les levés et les tests SHOM sont
conservés. NOAA reste disponible pour les courbes/dangers ; SHOM pour les dangers
et aides ; les autres fournisseurs restent en place. Si EMODnet est désactivé
par `MARINE_DISABLED_PROVIDERS=emodnet-dtm-2024`, les chiffres européens Z12+
renvoient une indisponibilité. Le fournisseur `noaa-soundings` utilise une
instance du client `MarineHTTP` existant avec `persistent_cache=false` ; aucune
base ni cache supplémentaire de profondeurs n'est créé. Les autres instances
conservent leur politique de cache historique.

## Contrat officiel vérifié en direct

Sources consultées :

- [DDS](https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024.dds)
- [DAS](https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024.das)
- [Formulaire ERDDAP](https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024.html)
- [Présentation EMODnet](https://emodnet.ec.europa.eu/en/bathymetry)
- [Métadonnées du produit et licence](https://sextant.ifremer.fr/geonetwork/srv/api/records/cf51df64-56f9-4a99-b1aa-36b8d7b743a1/formatters/xml)

| Élément | Valeur reçue |
|---|---|
| Dimensions | `[latitude=72000][longitude=75840]` |
| Axes | WGS84, croissants, centres des cellules |
| Latitude min/max | 15.000520833333333 / 89.99947916660017° |
| Longitude min/max | −35.99947916666667 / 42.99947916663591° |
| Pas latitude/longitude | 0.0010416666666657431 / 0.001041666666666261° |
| Résolution nominale | 1/960° = 1/16 minute d'arc, environ 116 m N–S, 85 m E–O à Toulon |
| `elevation` | Float32, mètres relativement au LAT, négatif sous le niveau de référence ; manquant NaN |
| `value_count` | Int32, manquant −1, plage valide 0…2147483646 |
| `interpolation_flag` | Byte, 0 non interpolé, 1 interpolé/extrapolé, manquant 127 |
| `cdi_index` | Int32, manquant −1, indice de provenance |

Le commentaire de `elevation` tranche la convention de signe même si son
`standard_name` est `depth`. Le produit est un DTM ; même le flag 0 ne transforme
pas sa cellule en sonde ponctuelle originale. Le DDS ne publie pas de variable
`cdi_reference` malgré l'attribut qui la mentionne : on conserve l'indice sans
inventer de lien individuel ni de précision individuelle.

Ces constantes sont celles du produit 2024 vérifié ; aucune requête de métadonnées
supplémentaire n'est nécessaire par tuile. Un changement des coordonnées, des
unités, du schéma ou une troncature est refusé par le décodeur CSV. Une évolution
du contrat officiel demanderait une nouvelle vérification de ces constantes.

## Géographie, sélection et requête

`Tile` valide Z0–16 et les indices XYZ ; la route conserve ses validations FastAPI.
La BBOX Web Mercator est convertie en WGS84 par le composant existant. Les
intervalles d'indices sont bornés aux dimensions du dataset, sans tampon de
voisinage. Propriété des centres : `ouest <= longitude < est` et
`sud < latitude <= nord`. Une cellule ne peut appartenir à deux tuiles adjacentes.

Les premiers indices demandés sont des multiples du stride **global**, jamais
d'une origine relative à la tuile. Les strides sont imbriqués :

| Zoom source | Stride latitude et longitude | Comportement |
|---|---|---|
| 0–11 | aucune requête | aucun chiffre |
| 12 | 32 | quelques cellules très espacées |
| 13 | 16 | cellules espacées, grille cohérente au déplacement |
| 14 | 4 | densité accrue |
| 15 | 2 | densité accrue |
| 16 | 1 | centres disponibles de la grille native |
| >16 côté affichage | données déjà récupérées, requêtes plafonnées à Z16 | aucun nouvel échantillon au-delà de la grille native |

Plafond dur : 64 cellules demandées et 64 cellules modélisées encodées par tuile.
Les dimensions actuelles donnent au plus 36 centres sélectionnés dans une tuile
entièrement couverte pour ces strides ; ce n'est pas une promesse de 36 labels
visibles, car valeurs manquantes, terre et collisions réduisent ce nombre.
Une bordure partiellement couverte peut ne contenir aucun centre sélectionné.

Exemple de syntaxe vérifiée, neuf cellules autour de Toulon :

```text
https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024.csv?
elevation[26964:2:26968][40290:2:40294],
value_count[26964:2:26968][40290:2:40294],
interpolation_flag[26964:2:26968][40290:2:40294],
cdi_index[26964:2:26968][40290:2:40294]
```

Les lignes et espaces ci-dessus servent à la lecture : l'URL réelle est une
seule ligne ; les crochets sont encodés `%5B`/`%5D`. Chaque variable reçoit les
mêmes bornes inclusives `[premier:stride:dernier]`, latitude puis longitude.
Aucune requête continentale/régionale, aucun WMS/GetFeatureInfo et aucune
extraction de chiffres depuis une image.

Le CSV comprend une ligne de noms, une ligne d'unités et une ligne par cellule
sélectionnée. Le décodeur exige la grille demandée complète, des coordonnées
alignées aux indices attendus à 1e-9° près, sans doublon ni cellule étrangère.
Les unités doivent être `degrees_north,degrees_east,m,,,`.

## Valeurs et propriétés MVT

Seule `elevation` alimente `value_m = -elevation` pour les valeurs finies
strictement négatives. Les valeurs positives, zéro et non finies sont exclues ;
les valeurs manquantes ne deviennent jamais zéro. Les métadonnées manquantes
restent absentes des propriétés MVT. Une valeur numérique malformée ou un flag
hors contrat fait échouer la réponse entière.

Contrat MVT conservé : couche `sounding`, propriétés `value_m` et `depth_label`.
Ajouts : `source=EMODnet`, `year=2024`, `dataset=bathymetry_dtm_2024`,
`vertical_datum=LAT`, `sounding_datum=LAT`, `nature=modeled_grid_cell`,
`derivation=modeled_grid_cell`, indices globaux et indicateurs disponibles.
`value_original` conserve l'élévation signée, `unit_original=m`, `provenance`
contient le DOI du produit. Aucune date d'observation ni incertitude n'est inventée.

Le flux GeoJSON actuel réutilise ces propriétés dans chaque `Feature` de sa
`FeatureCollection` ; la notion de couche MVT `sounding` concerne uniquement
l'encodage `.pbf` conservé.

Les labels seuls sont arrondis au mètre, demi-unités vers le haut : 12.4 → « 12 »,
12.5 → « 13 ». Une profondeur comprise entre 0 et 1 m affiche « <1 », sans faux
zéro. `value_m` conserve la valeur numérique reçue. Cette présentation n'exprime
aucune garantie de précision et ne convient pas à une marge sous quille.

La sélection legacy SHOM/NOAA reste utilisable par les outils et tests existants.
Les cellules EMODnet évitent cette seconde sélection pour conserver leur grille
globale ; elles sont dédupliquées par identité d'indice et ordonnées avant MVT.

## Réseau, erreurs et RAM

- Client `httpx.AsyncClient` dédié ; aucune utilisation de `MarineHTTP.get` ni
  de son SQLite, aucun corps écrit sur disque. L'adaptateur `cancellation_safe`
  utilise AnyIO, désormais déclaré explicitement dans `backend/requirements.txt`.
- 2 téléchargements simultanés maximum, départs espacés d'au moins 250 ms
  (4/s par processus), pas de retry par tuile.
- Timeout HTTP 6 s, connexion/pool 2 s ; délai total fournisseur 10 s incluant
  l'attente de concurrence et le débit. Enveloppe existante du service : 14 s.
- Après 429/503 : pause d'au moins 30 s, `Retry-After` numérique borné à 120 s ;
  après timeout/transport : pause de 5 s. Pour une date HTTP, pause par défaut 30 s.
- Réponse décompressée limitée à 256 Kio, lecture par blocs de 4096 octets,
  contrôle précoce de `Content-Length` et contrôle pendant la lecture.
- Cache final **RAM partagé entre MVT et GeoJSON** : 512 entrées, 32 Mio au total,
  TTL 300 s pour les succès complets. La clé distingue la tuile, la famille et le
  format. Les réponses dégradées ont un TTL de 15 s ; les échecs sans données
  répondent 503 et ne sont pas mis en cache. Aucun cache de corps CSV n'est ajouté.
  Les locks réunissent les chargements réussis d'une même clé. Le cache client
  de snapshots est distinct et décrit dans [NW-220](marine-zoom-persistence.md#récupération-et-budgets).
- Les routes de sondes MVT et de snapshots GeoJSON surveillent la déconnexion ASGI
  toutes les 100 ms et annulent le travail,
  y compris l'attente d'un lock. L'adaptateur `cancellation_safe` attend la fermeture
  HTTP et la libération du sémaphore avant de propager l'annulation, même lorsqu'elle
  provient de l'échéance fournisseur.
  Une demande annulée n'alimente pas le cache ; les autres demandeurs peuvent
  reprendre un téléchargement. Le travail déjà fini peut rester en RAM.
- Les logs contiennent indices XYZ, nombre de cellules/points, octets, temps
  et raisons d'erreur ; aucun corps CSV/MVT n'est journalisé.

### Réponses de la route MVT conservée

| Cas | HTTP | `X-NoWave-Marine-Status` |
|---|---|---|
| Profondeurs disponibles | 200 MVT | `ok` |
| Zone couverte sans profondeur sélectionnée valide | 200 MVT vide | `empty` |
| Entièrement hors rectangle de couverture | 200 MVT vide | `outside-coverage` |
| Z0–11 | 200 MVT vide | `below-minzoom` |
| HTTP fournisseur, timeout, transport, CSV malformé/limites | 503 JSON | `unavailable` |
| Déconnexion observée | 499 (client déjà parti) | sans objet |
| XYZ invalide | 422 JSON | sans objet |

Les raisons `http-xxx`, `timeout`, `transport`, `malformed-csv`, `body-limit`,
`cell-limit`, `cooldown` restent distinctes dans le fournisseur et les logs.
Toutes les réponses valides et les 503 des sondes, en MVT comme en GeoJSON,
portent `Cache-Control: no-store`. Le tableau ci-dessus décrit les corps MVT ;
la route mobile actuelle renvoie du GeoJSON pour ses succès. Les en-têtes des
autres familles sont conservés.

Les limites sont par processus ; multiplier les workers multiplierait le débit
total. Le lancement Uvicorn local/déploiement du dépôt utilise un processus.

## Flutter, attribution et limites de validation

### Paramètres historiques du client MVT

La source vectorielle initiale conservait son identifiant, utilisait
`minzoom=12`, `maxzoom=16` et `?v=depths-4` pour distinguer les anciennes tuiles.
Elle seule recevait `volatile=true`, avec préchargement désactivé et délai réseau
de 250 ms. Ces paramètres décrivent l'ancienne `VectorSource` ; ils ne constituent
pas la configuration des sources GeoJSON alimentées par `MarineViewport`.

### Rendu actuel et attribution

Le label accepte `nature=modeled_grid_cell` ou `nature=point_sounding` ; la
sélection géographique des fournisseurs se fait exclusivement dans le backend.
NOAA conserve ses valeurs ponctuelles et décimales publiées, son datum lorsqu'il
est réellement renseigné, et son absence de datum sinon. Les levés SHOM archivés
ne sont pas remis dans le flux MVP.

Le style NoWave utilise le slot MIDDLE et affiche les labels à partir de Z13.
L'expression de taille interpole 10.5, 11.5, 12.5 et 13.5 aux paliers Z12, Z14,
Z16 et Z18. Le halo est sombre, avec `textAllowOverlap=false` et
`textIgnorePlacement=false`.
Les dangers/aides/bouées restent au slot TOP ; les signalements et le GPS ne
sont pas modifiés. L'espacement natif des symboles décide des labels visibles.

L'attribution fournit le nom du Consortium, le titre du produit 2024, le DOI,
CC BY 4.0, la mention de profondeurs modélisées en mètres/LAT, et la sélection
et l'arrondi effectués par NoWave. L'attribution SHOM archivée est marquée hors
chiffres du MVP. Le registre `/marine-sources` distingue également ce statut.
Le bouton d'attribution existant reste accessible sur la carte.

**Interdit pour la navigation et la sécurité en mer.** Ni passage garanti,
ni marge sous quille, ni tirant d'eau admissible, ni remplacement des cartes
officielles. Une cellule sous LAT peut être inadéquate à un littoral récent ou
à un bassin portuaire fin ; le modèle n'est pas un masque côtier actuel.

### Portée des validations

Les contrôles de `volatile`, des URL de tuiles et de l'overzoom de la source
vectorielle appartiennent à la validation du client MVT initial. Les captures
et interrogations natives sur le LGN LX1 citées dans ces comptes rendus restent
des preuves datées des vues examinées. Le contrat de sources GeoJSON et de
couches actuel est décrit par les
[tests Flutter correspondants](../../mobile/test/features/map/data/hydrography_layer_test.dart) ;
la recette de conservation et de rechargement du style relève de
[NW-220](marine-zoom-persistence.md#vérification).
Les règles du fournisseur ERDDAP sans persistance de corps CSV et les en-têtes
des sondes restent celles décrites dans la section réseau.
L'effet de tous les caches natifs Mapbox/Android ou d'un éventuel proxy distant
n'est pas audité. Aucun cache existant n'a été effacé ; aucune absence totale
de stockage natif durable n'est affirmée.

Les comptes rendus détaillés de la première validation et de la correction marine finale restent accessibles dans l'historique Git précédant le nettoyage. Le [bilan Stage 4](../NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf) synthétise les vérifications datées sans certifier une couverture complète de tous les appareils et services distants.
