# Seuils et conservation maritimes — NW-220

## Contrat

Le zoom est celui de la caméra Mapbox, fractionnaire. `MarineZoom` centralise
les seuils Flutter : raster 5 ; préparation des ports 6 ; ports 8 ; enrichissement
portuaire et préparation des marques 10 ; marques complètement opaques et
préparation des profondeurs 12 ; courbes, étiquettes et sondes 13. Les couches
ont un `minZoom` et aucun seuil supérieur de disparition.

**Décision utilisateur de la validation finale :** les marques apparaissent
progressivement entre Z10 et Z12 (0 % à Z10, 50 % à Z11, 100 % à Z12).
Cette décision remplace la règle « invisibles avant Z12 » encore inscrite dans
Linear ; le ticket n'est pas modifié dans cette mission. Les données sont
préchargées à Z10, mais les sources de placement des marques restent vides à
Z10 exactement et en dessous, pour ne pas réserver de collisions invisibles.

Le raster conserve la palette marine NoWave avec le rendu `marine-visual-7`
(bilinéaire WMS et continuité locale des couleurs, sans mesure ajoutée),
masques et crédits conservés. Voir le [contrat du rendu raster](marine-sources.md#masque-littoral-raster--correction-du-18-octobre-2026). Son opacité nominale vaut 1 dès Z5. Le slot MIDDLE
le place au-dessus du fond marin du globe. Les infrastructures et symboles
installés ensuite restent au-dessus ; la terre du raster est transparente.

## Récupération et budgets

Le nouvel endpoint public `marine-features/{family}/{z}/{x}/{y}.geojson` partage
les fournisseurs, la fusion, le cache HTTP persistant et les limites existantes.
Il n'ajoute aucun fournisseur. Les routes MVT historiques sont conservées.
Les cinq routes XYZ GeoJSON partagent le quota Nginx marin, distinct de celui
de l'API métier ; les métadonnées et les autres routes gardent leur protection.
Seules les familles harbours, seamarks, depth-contours, soundings et
underwater-hazards sont acceptées. Les contours utilisent uniquement Z12 ; les
ports acceptent Z6–Z14 et les autres snapshots Z10–Z14, avec les seuils de
récupération propres aux familles. Les sondes conservent leur résolution native
jusqu'à Z16 ; les autres familles restent bornées à Z14. Un XYZ invalide est rejeté avant tout appel.

`MarineViewport` récupère explicitement les corps de réponse, indépendamment du
placement. Le préchargement n'est donc pas une simple déclaration de source.
À Z10, marques et dangers sont effectivement demandés à la résolution Z12 ;
à Z12, les profondeurs sont également demandées. La demande correspond aux
limites géographiques réelles de la caméra, rotation, inclinaison et padding
compris, avec une marge d'une cellule. Les plages XYZ restent paresseuses : une
vue mondiale ne crée pas une liste de millions de cellules. L'antiméridien est
déroulé avant normalisation des X et les Y restent dans les limites Mercator.

Le groupe de travail comporte au maximum 64 cellules, toutes familles réunies,
avec deux téléchargements GeoJSON simultanés. Les cellules visibles passent
avant la marge, par anneaux autour du centre ; les familles alternent à priorité
égale. Le calcul cherche d'abord une couverture de 48 cellules visibles pour
réserver seize emplacements à la transition, au détail central ou à la marge.
Si nécessaire, il réduit les résolutions de base, aux minima Z6 pour les ports
et Z12 pour les autres familles ; les courbes restent toujours Z12. Les places
restantes enrichissent le centre à la résolution demandée, puis la marge.
Si les minima dépassent encore le budget, les plages conservent la demande
géographique complète, mais seules les cellules centrales admissibles sont
chargées. Le fond mondial GEBCO assure alors la couverture périphérique.
À Z6, une cellule portuaire peut agréger seize enfants Open Waters Z8 ; deux
requêtes de l'application ne signifient pas deux lectures fournisseur au total.

Cache client : 64 snapshots / 12 Mio de JSON encodé, plus au maximum 8 000 points
conservés / 4 Mio encodés. Les objets Dart et les buffers GPU ne sont pas inclus
dans ces budgets : la mémoire réelle doit être mesurée sur l'appareil, y compris
les buffers des deux réponses en cours et la mosaïque de rendu. La demande
réseau et la couverture affichée sont distinctes. Une cellule complète remplace
immédiatement sa propre zone, même si une voisine échoue. Les anciennes cellules
couvrent les trous restants ; elles sont libérées lorsque la relève est complète
ou lorsqu'elles quittent la région utile. Une réponse vide valide couvre sa zone,
une réponse dégradée ou HTTP 503 ne supprime pas le secours existant.

La soustraction des couvertures suit un quadtree, sans grille étendue au zoom
le plus fin. Les lignes et surfaces anciennes sont découpées aux régions
restantes, avec `clipper2 0.0.3` pour les polygones, trous et parties disjointes.
Seuls les fragments d'affichage polygonaux sont calculés à 1e-9 degré ; les
snapshots sources restent intacts. Les contours des dangers sont découpés comme
des lignes d'origine : les nouvelles limites de relève ne deviennent pas des
traits physiques. Les fragments adjacents d'une même identité sont réunis,
sans supprimer une partie parce que son identifiant source est déjà présent.

L'admission dans le cache est atomique avec le retrait des cellules remplacées
et l'éviction éventuelle de marges moins prioritaires. Une saturation conserve
le secours utile, réduit encore la résolution admissible ou diffère la cellule.
Les refus de budget ne sont pas des erreurs réseau et ne provoquent pas de
téléchargement à chaque temporisation. Chaque
réponse est limitée à 4 Mio / 6 000 objets côté serveur ; le cache serveur final
reste borné à 512 entrées / 32 Mio, tous formats confondus. En saturation, les
nouveaux snapshots sont refusés si aucune relève respectant les budgets ne peut
être admise. Cela peut limiter l'enrichissement ; le fond mondial reste présent.

Le client annule les requêtes dépassées et suspend son travail en arrière-plan.
Une erreur n'entre jamais dans le cache comme réponse vide. Les diagnostics
séparent le statut HTTP, une réponse dégradée et un succès avec zéro objet.
Un nouvel essai borné a lieu après temporisation de 15–16 secondes. Une réponse
partielle est réessayée, avec union par identité des courbes précédentes et des
nouveaux objets. Le cache HTTP existant fixe les durées amont. Les corps publics
voyagent sans en-tête Firebase ; les services métier et les reports gardent
`API_BASE_URL` et leurs règles d'authentification.
Les diagnostics d'erreur et temporisations sont limités aux cellules demandées
par la vue actuelle ; ils sont purgés quand une cellule quitte cet ensemble.
Les métriques `planned_visible`, `wanted`, `budget_deferred` et `request_zooms`
séparent la demande géographique adaptée, le groupe de travail, les refus de
budget et les résolutions de base effectivement demandées.

## Ports

Open Waters reste l'unique source. `HarbourProvider` conserve l'identité MVT
amont publiée, distincte d'un simple numéro OSM dont le type d'élément n'est pas
fourni. Aucun rapprochement nom/proximité n'est ajouté.

La sélection utilise les positions projetées réelles de Mapbox et des boîtes
écran conservatrices de 32,88 points logiques. L'ordre initial est déterministe :
objets nommés, catégorie publiée, puis identité. Chaque identité sélectionnée
reçoit ensuite un ordre conservé. Les collisions sont recalculées sur les
positions projetées à chaque caméra : un perdant redevient éligible dès que son
représentant quitte l'écran ou cesse de le bloquer. Les nouveaux candidats
passent après les ports conservés. Les coordonnées du premier point réellement
récupéré sont gardées ;
on ne substitue pas un point différemment quantifié d'une tuile plus détaillée.
Les sources GeoJSON sont reconstituées après rechargement du style.

Une rotation ou une inclinaison peut forcer deux anciens représentants à se
chevaucher : le plus ancien reste dessiné, l'autre reste consultable par appui
long. Au zoom avant sans cette collision forcée, les nouveaux ports n'évincent
pas les anciens. Le retour sous Z8 réinitialise la sélection. Les objets sortis
du champ et du voisinage utile peuvent être libérés. Mapbox quantifie ses tuiles
internes : les coordonnées d'une requête de rendu à faible zoom peuvent être
arrondies, même lorsque les coordonnées GeoJSON conservées restent identiques.

## Marques et interaction

Les cinq types de bouées et toutes les aides fixes disponibles suivent le fondu
linéaire Z10–Z12, à opacité nominale 1 dès Z12. Les dangers ponctuels suivent le
même fondu ; leurs surfaces et contours gardent respectivement leur opacité
graphique nominale .07 et .8 à partir de Z12. Les règles IALA, PNG et valeurs
sources sont conservées. La couche normale de bouées exclut les cardinales et dangers isolés ;
une couche de sécurité séparée utilise `iconAllowOverlap: true`.
Les balises fixes cardinales et de danger isolé utilisent leur propre couche de
sécurité, même quand leur pictogramme est neutre faute d'attributs de couleur.
Aucune priorité ne dépend uniquement d'un sort-key entre couches différentes.
Les expressions de chevauchement par objet exposées dans Flutter 2.30.1 ont été
refusées par le moteur Android : elles ne sont pas utilisées.

Les dangers physiques sont placés au-dessus des bouées ordinaires, avec
collisions lisibles. Les couches de sécurité restent rendues même si des
symboles ordinaires ou prioritaires se chevauchent. Les reports sans slot restent
au-dessus, avec leurs interactions intactes. Un appui long liste les véritables
ports, marques et dangers ponctuels proches, même si leur symbole est masqué.
Deux objets exactement superposés peuvent être impossibles à lire séparément ;
la liste permet d'en consulter les identités descriptives sans les déplacer.

## Courbes et sondes

La récupération utilise les géométries WGS84 normalisées originales, pas les
fragments MVT quantifiés différemment à chaque zoom. Les courbes sont découpées
sur une grille Z12 canonique et non bufferisée. L'identifiant de rendu est
`identité_source@12/x/y` ; l'identité originale reste dans les propriétés.
Les coordonnées des bords sont calculées de façon identique entre voisins.
Les segments exactement situés sur un bord sont possédés par une seule cellule.
Les objets partageant uniquement une profondeur ou une proximité ne sont pas
fusionnés. Les propriétés de profondeur, datum, précision et licence sont gardées.

Toutes les courbes récupérées, y compris celles dont `display_minzoom` vaut 14,
sont disponibles dès le préchargement Z12. Le filtre ne fait qu'ajouter des
courbes quand leur seuil est atteint. Les lignes ne dépendent plus des étiquettes,
ne s'éteignent plus à Z15 et gardent leur opacité graphique nominale (.72/.48).
Les annotations ont leurs propres collisions. Les snapshots déjà récupérés sont
conservés tant que leur cellule intersecte le champ géographique réel ou son
voisinage utile. Un rafraîchissement ajoute de nouvelles identités sans remplacer
les géométries précédentes. Une réponse complète explicitement vide confirme
l'absence de données et vide la cellule, y compris ses points retenus ; une
réponse partielle vide ne le fait jamais. Le rechargement du style conserve cet état.

Les sondes NOAA peuvent être préparées dès Z12 ; la sélection réutilise la grille
spatiale existante de Z14, sans synthétiser de profondeur. Les profondeurs
EMODnet restent des cellules modélisées, distinctes des observations ponctuelles.

**Les courbes généralisées EMODnet 2022 conservées ne sont pas des levés de
précision portuaire, ni des données officielles utilisables pour la navigation.**
Aucune courbe, couleur, catégorie ou profondeur manquante n'est fabriquée.
La couverture demeure celle des fournisseurs. Les sorties du champ, limites de
budget, données réellement indisponibles et redémarrages de processus ne sont
pas une promesse de conservation hors ligne illimitée.

## Vérification

Les scripts `mobile/tool/nw220_*validation.py` pilotent l'extension VM de la vraie
application `lib/main.dart`, avec requêtes natives de rendu et captures ADB.
`MarineDebug` n'enregistre cette extension qu'en debug. Ils ne modifient ni GPS,
compte, signalements, permissions ni stockage applicatif. Les preuves restent
locales dans `test-results/NW-220/`, ignoré par Git. Une compilation seule ou une
fixture n'est jamais présentée comme validation Android réelle.


## Reprise du raster pendant les déplacements rapides

Les détails bathymétriques constituent une superposition visuelle au fond mondial
GEBCO. Si le fournisseur ou le masque côtier est indisponible, leur route PNG
renvoie HTTP 503 avec le JSON d'erreur existant, `Cache-Control: no-store`,
`X-NoWave-Marine-Status: unavailable` et `Retry-After: 15`. Une panne ne peut
plus être acceptée comme un PNG transparent réussi à la place d'une ancienne
tuile utile. Les tuiles transparentes réellement valides, notamment hors
couverture, gardent HTTP 200. Toutes les familles GeoJSON/MVT utilisent le même
contrat 503 explicite. Les caches fournisseur et leurs temporisations restent
actifs et le fond mondial reste installé sous le détail régional.

La source régionale utilise désormais `prefetchZoomDelta: 4`, comme le fond
GEBCO, pour préparer une couverture de résolution inférieure. Le cache disque,
les tuiles parentes, les limites géographiques et le fondu restent actifs.

Les appels WMS partagent un délai de reprise après une panne : 5 secondes pour
une erreur réseau, 30 secondes pour une limitation ou erreur serveur, prolongées
par `Retry-After` le cas échéant. Les demandes HTTP abandonnées sont détectées ;
un rendu encore en file est supprimé lorsque tous ses demandeurs sont partis.
Un rendu déjà commencé conserve son emplacement jusqu'à sa fin, afin de ne pas
multiplier les workers synchrones. Les demandes partagées encore utiles et les
tuiles déjà calculées restent réutilisables.

Le service HTTP natif Mapbox est limité à deux requêtes simultanées par hôte,
toutes sources confondues. Les deux requêtes GeoJSON Dart gardent leur budget
distinct ; les requêtes métier disposent ainsi d'une marge sous la limite de
trente connexions du proxy. Ce plafond ne constitue pas une limite de débit
en requêtes par seconde : les délais de gestes et protections du serveur restent
actifs.

## Limitation géographique du raster EMODnet

La source native `nowave-bathymetry` utilise les `bounds` publiées pour
`emodnet:mean_multicolour` : ouest −73,125°, sud 5,625°, est 45°, nord 90°,
avec la latitude nord ramenée à 85,051129° pour Web Mercator. Le SDK ne demande
pas de tuiles entièrement extérieures à cette emprise. Elle inclut les Caraïbes
publiées par ce WMS ; il s'agit d'une enveloppe, pas d'une garantie de données
sur chaque pixel intérieur. Source : [GetCapabilities EMODnet](https://ows.emodnet-bathymetry.eu/wms?service=WMS&version=1.3.0&request=GetCapabilities),
vérifié le 23 octobre 2026.

La route PNG et l'adaptateur WMS vérifient aussi cette intersection. Une ancienne
application ou un appel direct hors emprise reçoit une tuile transparente
`outside-coverage`, sans accès au cache des rendus, sans appel EMODnet et sans
masque côtier. Les tuiles à cheval sur la frontière restent éligibles ; une tuile
qui touche seulement le bord est extérieure. Ce contrôle ne modifie pas les
requêtes du fond mondial GEBCO, qui utilise une source distincte.
