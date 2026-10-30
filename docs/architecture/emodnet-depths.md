# Profondeurs modélisées EMODnet 2024 — contrat MVP

Implémentation locale du 18 octobre 2026. Ce document actualise uniquement le
flux des chiffres de profondeur décrit dans `hydrography.md` ; les courbes et
dangers conservent leurs fournisseurs et leur fonctionnement.

## Flux et sélection

```text
Flutter HydrographyLayer / Mapbox VectorSource (Z12, max source Z16)
  → GET /api/v1/map/soundings/{z}/{x}/{y}.pbf
  → MarineTileService (cache MVT RAM existant, requêtes identiques sérialisées)
  → EmodnetDepthProvider (client HTTP dédié sans cache disque)
  → ERDDAP griddap bathymetry_dtm_2024.csv, sélection bornée par indices
  → vérification stricte du CSV, cellules marines normalisées en mémoire
  → encode_hydro_tile, couche MVT « sounding », extent 4096
  → labels numériques depth_label
```

`MarineTileService.select` réserve les chiffres européens à `emodnet-dtm-2024`.
Depuis la correction du 18 octobre et le choix utilisateur, les sondes ENC NOAA
sont rétablies dans leur couverture, hors EMODnet, à partir de Z14. Cette
sélection est géographique : aucun repli NOAA lors d'une panne EMODnet, et aucun
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
| >16 dans Mapbox | réutilisation de Z16 | aucun nouveau point créé |

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

Contrat conservé : couche `sounding`, propriétés `value_m` et `depth_label`.
Ajouts : `source=EMODnet`, `year=2024`, `dataset=bathymetry_dtm_2024`,
`vertical_datum=LAT`, `sounding_datum=LAT`, `nature=modeled_grid_cell`,
`derivation=modeled_grid_cell`, indices globaux et indicateurs disponibles.
`value_original` conserve l'élévation signée, `unit_original=m`, `provenance`
contient le DOI du produit. Aucune date d'observation ni incertitude n'est inventée.

Les labels seuls sont arrondis au mètre, demi-unités vers le haut : 12.4 → « 12 »,
12.5 → « 13 ». Une profondeur comprise entre 0 et 1 m affiche « <1 », sans faux
zéro. `value_m` conserve la valeur numérique reçue. Cette présentation n'exprime
aucune garantie de précision et ne convient pas à une marge sous quille.

La sélection legacy SHOM/NOAA reste utilisable par les outils et tests existants.
Les cellules EMODnet évitent cette seconde sélection pour conserver leur grille
globale ; elles sont dédupliquées par identité d'indice et ordonnées avant MVT.

## Réseau, erreurs et RAM

- Client `httpx.AsyncClient` dédié ; aucune utilisation de `MarineHTTP.get` ni
  de son SQLite. Pas de dépendance ajoutée, aucun corps écrit sur disque.
- 2 téléchargements simultanés maximum, départs espacés d'au moins 250 ms
  (4/s par processus), pas de retry par tuile.
- Timeout HTTP 6 s, connexion/pool 2 s ; délai total fournisseur 10 s incluant
  l'attente de concurrence et le débit. Enveloppe existante du service : 14 s.
- Après 429/503 : pause d'au moins 30 s, `Retry-After` numérique borné à 120 s ;
  après timeout/transport : pause de 5 s. Pour une date HTTP, pause par défaut 30 s.
- Réponse décompressée limitée à 256 Kio, lecture par blocs de 4096 octets,
  contrôle précoce de `Content-Length` et contrôle pendant la lecture.
- Cache **MVT RAM existant** : 512 tuiles, 32 Mio, TTL 300 s pour les succès.
  Aucun second cache de données/CSV. Les pannes ne sont pas mises en cache.
  Les locks existants réunissent les chargements réussis d'une même tuile.
- La route surveille la déconnexion ASGI toutes les 100 ms et annule le travail,
  y compris l'attente d'un lock. Les ressources réseau et sémaphores sont libérées.
  Une demande annulée n'alimente pas le cache ; les autres demandeurs peuvent
  reprendre un téléchargement. Le travail déjà fini peut rester en RAM.
- Les logs contiennent indices XYZ, nombre de cellules/points, octets, temps
  et raisons d'erreur ; aucun corps CSV/MVT n'est journalisé.

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
Toutes les réponses valides et les 503 de cet endpoint portent
`Cache-Control: no-store`. Les en-têtes des autres familles sont conservés.

Les limites sont par processus ; multiplier les workers multiplierait le débit
total. Le lancement Uvicorn local/déploiement du dépôt utilise un processus.

## Flutter, attribution et limites de validation

La source de chiffres conserve son identifiant, passe à `minzoom=12`, reste à
`maxzoom=16`, et utilise désormais `?v=depths-4` pour distinguer les anciennes tuiles.
Elle seule reçoit `volatile=true`. Préchargement désactivé, délai réseau 250 ms.
Le label accepte `nature=modeled_grid_cell` ou `nature=point_sounding` ; la
sélection géographique des fournisseurs se fait exclusivement dans le backend.
NOAA conserve ses valeurs ponctuelles et décimales publiées, son datum lorsqu'il
est réellement renseigné, et son absence de datum sinon. Les levés SHOM archivés
ne sont pas remis dans le flux MVP.

Le style NoWave est conservé : slot MIDDLE, tailles 10.5 à Z12 puis 11.5/12.5 à
Z14/Z16, halo clair, `textAllowOverlap=false`, `textIgnorePlacement=false`.
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

La configuration `volatile`, les en-têtes et l'absence de persistance Python
sont vérifiés par tests/lecture du code. La correction marine finale ajoute
des captures et interrogations natives sur le LGN LX1 : collisions, overzoom,
rechargement du style et URL locales sont vérifiés dans les vues documentées.
L'effet de tous les caches natifs Mapbox/Android ou d'un éventuel proxy distant
n'est pas audité. Aucun cache existant n'a été effacé ; aucune absence totale
de stockage natif durable n'est affirmée.

Les comptes rendus détaillés de la première validation et de la correction marine finale restent accessibles dans l'historique Git précédant le nettoyage. Le [bilan Stage 4](../NoWave_Preuves_et_resultats_des_tests_29-10-2026.pdf) synthétise les vérifications datées sans certifier une couverture complète de tous les appareils et services distants.
