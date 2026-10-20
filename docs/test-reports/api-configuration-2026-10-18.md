# NoWave — Centralisation des API — 18 octobre 2026

La configuration du code utilise désormais `API_BASE_URL` comme seule adresse de
backend. Les deux anciennes variables marines n'ont plus d'effet. Les essais
Android distinguent l'application normale et un diagnostic cartographique isolé.
**Validation distante bloquée par l'absence des endpoints déployés.**

## A. État Git initial

Branche conservée : `feature/marine-bathymetry` ; HEAD vérifié :
`204373489f47fbd41993960f245aaf20ff14ba1d`. Au démarrage : 22 fichiers suivis
modifiés, 45 non suivis. Une copie externe des 715 fichiers suivis ou non ignorés,
du diff, de l'index et de la configuration privée a précédé les changements :
`/home/palms/nowave-snapshots/api-config-20261018T160052Z`.
Les développements marins antérieurs, données SHOM et icônes sont préservés.

## B. Anciennes variables et usages

`ApiService` et les tuiles de signalements utilisaient déjà `API_BASE_URL`.
`MarineTiles` lisait `MARINE_API_BASE_URL` avec repli vers cette base ;
`MarineMapController` lisait séparément `BATHYMETRY_TILES_URL`.
La recherche couvre Dart, tests, documentation, scripts et workflows, dont les
adresses locales. Aucune de ces deux variables n'est désormais lue dans
`mobile/lib`. Les références restantes expliquent la migration, testent leur
absence d'effet ou appartiennent aux rapports historiques conservés.
Les adresses locales des tests/exemples ne sont pas des valeurs de production.

## C. Architecture retenue

`ApiConfig.resolve`, `endpoint` et `tileTemplate` construisent les adresses HTTP,
MVT et PNG. La base doit être HTTP(S), avoir un hôte et un port valide, sans
identifiants ni fragment ; une base absente provoque une erreur explicite.
Slash final facultatif, préfixe et paramètres de requête préservés ; les versions
explicites remplacent leur ancienne valeur. Les jetons `{z}/{x}/{y}` restent
littéraux pour le SDK. Les chemins applicatifs absolus et traversées `..` sont
refusés avant envoi d'un en-tête d'authentification.

Les injections existantes restent disponibles. Aucun fournisseur ni backend
personnel n'est ajouté par défaut. L'ajout d'une famille de tuiles appelle le
même générateur avec son chemin ; aucune variable d'environnement supplémentaire.

## D. Fichiers de cette intervention

15 fichiers existants modifiés, comparés à la copie initiale, et trois nouveaux
fichiers, dont ce rapport :

- Configuration : `mobile/lib/core/api/api_config.dart`, `api_service.dart`.
- Raster : `mobile/lib/core/map/marine/marine_map_controller.dart`.
- Sources : `mobile/lib/features/map/data/marine_tiles.dart`, `report_tiles.dart`,
  `hydrography_layer.dart`, `buoy_layer.dart`, `port_layer.dart`.
- Documentation : `mobile/.env.example.json`, `mobile/README.md`,
  `docs/architecture/marine-sources.md`.
- Tests existants : `mobile/test/core/api/api_service_test.dart`,
  `mobile/test/features/map/data/{buoy_layer,port_layer,hydrography_layer}_test.dart`.
- Nouveaux tests : `mobile/test/core/api/api_config_test.dart`,
  `mobile/test/features/map/data/api_sources_test.dart`.
- Nouveau rapport : ce fichier.

Les fichiers hydrographiques déjà non suivis au départ restent non suivis.
Le backend, les règles métier, GPS, styles et données ne sont pas modifiés.
Le paramètre d'exemple MapTiler inutilisé a été retiré ; Mapbox reste configuré.

## E. Endpoints générés

Devant chaque chemin ci-dessous : `API_BASE_URL`, avec son éventuel préfixe.

| Usage | Chemin |
| --- | --- |
| Profil | `api/v1/users/me` |
| Signalements et photos | `api/v1/reports`, `api/v1/reports/{id}/photo` |
| Alertes | `api/v1/users/me/alerts` |
| Tuiles de signalements | `api/v1/map/tiles/{z}/{x}/{y}.mvt` |
| Bathymétrie | `api/v1/map/bathymetry/{z}/{x}/{y}.png?v=coast-1` |
| Isobathes | `api/v1/map/depth-contours/{z}/{x}/{y}.pbf?v=3` |
| Sondes | `api/v1/map/soundings/{z}/{x}/{y}.pbf?v=depths-4` |
| Dangers | `api/v1/map/underwater-hazards/{z}/{x}/{y}.pbf?v=3` |
| Bouées, balises, phares et feux | `api/v1/map/seamarks/{z}/{x}/{y}.pbf` |
| Ports | `api/v1/map/port-infrastructure/{z}/{x}/{y}.pbf` |
| Métadonnées et crédits | `api/v1/map/marine-sources` |

Les autres services continuent d'utiliser `ApiService` et les chemins FastAPI
existants. Les crédits HTML échappent l'URL générée.

## F. Configuration locale

Base testée : `http://127.0.0.1:8004/`, avec reverse USB sur le LGN.
`/health` : 200 ; `/health/ready` : 503. OpenAPI local JSON confirme les routes.
Les sept endpoints marins répondent 200 : métadonnées JSON, raster PNG, cinq
familles PBF au type `application/vnd.mapbox-vector-tile`. Un second sondage
réel décode le PNG RGBA 256 × 256 et les cinq PBF : couches `seamark`,
`water_polygons`, `pier_lines`, `pier_polygons`, `depth_contour`, `sounding` et
`underwater_hazard` ; une tuile portuaire au large peut être vide.
Cache raster : `public, max-age=86400` ; autres MVT marines :
`public, max-age=300`, sauf sondes `no-store`. Le client garde le raster
`coast-1`, les MVT `v=3` et les sondes `depths-4`, `volatile: true`.

Le processus local n'a ni base applicative configurée ni configuration Firebase
Admin. La base mentionnée dans la configuration privée du projet n'écoute pas
sur le port attendu. Le backend marin seul ne permet donc pas le parcours
applicatif complet. Aucun proxy, utilisateur artificiel ou contournement
d'authentification n'a été ajouté.

## G. Configuration distante

Base réellement configurée : `https://api.no-wave.fr/`.
`/health` et `/health/ready` : 200 JSON. `/version` : 200 JSON, version
`a42bea967dea6a6a39f29106af42a84614e83449`.
`/openapi.json` renvoie 200 HTML : il ne constitue pas une preuve de schéma API.
Les sondages publics du profil et des tuiles de signalements renvoient 401,
conformément à leur authentification ; `GET /api/v1/reports` renvoie 405.

Les sept routes marines du tableau, métadonnées comprises, renvoient 404 JSON,
y compris avec les versions de cache réellement utilisées. Le 404 raster porte
`Cache-Control: max-age=14400` ; les autres 404 testés n'en portent pas.
**Validation distante bloquée par l'absence des endpoints déployés.**
Aucune substitution silencieuse vers le local, aucun déploiement ni push.

## H. Services applicatifs

La nouvelle APK distante normale, construite depuis `lib/main.dart`, obtient
un vrai `UserProfile` via `ProfileService.getCurrentProfile` dans la session
existante. La requête native des objets rendus trouve un signalement existant.
Ses sept sources backend utilisent bien l'adresse distante unique. Aucun
nouveau signalement n'a été publié. Les photos, notifications et écritures
métier ne font pas l'objet d'un nouvel essai réel ; leurs tests existants passent.

Les services Firebase, Mapbox et le téléchargement des photos signées conservent
leurs adresses propres. Leurs tokens ne sont pas des bases d'API NoWave.

## I. Validation Android

LGN LX1 `AV5PJV6328H03108`, Android 15 / API 35, USB. Aucune désinstallation ni
effacement de données. Disponibilité demandée et confirmée avant manipulations.
Les captures sont acceptées uniquement lorsque NoWave est au premier plan ;
les fenêtres d'autres applications ne constituent pas des preuves NoWave.

Trois nouvelles APK debug ont été construites sans aucune des deux anciennes
variables, à partir d'une copie temporaire filtrée de la configuration privée :

- APK distante normale : `API_BASE_URL=https://api.no-wave.fr/`.
- APK locale normale : `API_BASE_URL=http://127.0.0.1:8004/`.
- Diagnostic local cartographique : même base unique, point d'entrée temporaire
  hors dépôt, initialisant Firebase et le vrai `MapScreen`. Il permet de vérifier
  les routes publiques et le SDK natif lorsque le profil local n'est pas servi.
  Il ne teste pas le parcours authentifié, ne fournit ni faux profil ni fixtures,
  et n'est pas une validation complète de l'application locale.

L'APK distante a été identifiée par son empreinte SHA-256 après installation :
`8e0bac7c53ad728592342ad8d8f4810841b9f043895beecc966c94469c42e8c1`.
Le SDK contient sept sources backend distantes, les placeholders XYZ littéraux
et les versions attendues. La requête native trouve un signalement existant ;
les familles marines sont vides, conformément aux 404 distants.

L'APK locale normale a également été identifiée par SHA-256. Le vrai appel du
profil retourne `ApiException`, statut 401 ; l'écran affiche « Impossible de
récupérer votre profil ». Aucun appui sur Déconnexion ni effacement de session.
Les empreintes de session sont identiques entre APK distante et locale.

Le diagnostic marin installe six sources backend locales avec les URLs
attendues ; le masque d'eau Mapbox conserve sa source propre. À z12, la requête
native rend un échantillon de 24 bouées, une balise principale, deux phares,
cinq labels d'isobathes, quatre sondes et quinze dangers. Ce sont des objets
publics réellement décodés par le SDK, pas des fixtures. Captures relues à
z6, z9 et z12 : raster en mer, masque côtier, gradation et symboles présents.
Le rechargement du style suivi d'installations répétées garde les sources et
couches uniques, les URLs/versionnements et les icônes fixes attendues.

À z14,8 dans le port de Toulon, les requêtes natives trouvent des digues,
pontons, bouées, balises locales, sondes et dangers (échantillon plafonné à
trois objets par couche). La capture confirme les détails portuaires.
Le bouton GPS ramène la caméra à z15,5, sans suivi continu ; après un geste
latéral, le centre reste stable et le suivi reste désactivé. Captures relues
et états natifs enregistrés.

À la demande explicite de l'utilisateur, l'APK fonctionnelle d'avant cette
intervention a été restaurée avec `adb install -r`. Empreinte installée identique
à la sauvegarde :
`730b888db4c2f97fb53b3f5e04957effd78f773ec14fc734311b24edf79fc0a4`.
Le profil renvoie `UserProfile`, l'empreinte de session Firebase est identique
à celle des nouvelles APK, la carte fonctionne et les réglages de rotation
initiaux sont rétablis. Cette restauration est une restitution demandée, pas
une preuve de la nouvelle configuration.
[Capture après restitution](../../test-results/api-config-2026-10-18/restored-original-apk.png).

Captures locales de preuve : [APK distante normale](../../test-results/api-config-2026-10-18/remote-z12.png),
[erreur de profil locale](../../test-results/api-config-2026-10-18/local-profile.png),
[diagnostic marin à z12](../../test-results/api-config-2026-10-18/map-local-z12.png),
[ports à z14,8](../../test-results/api-config-2026-10-18/local-marine-port-z14.8.png),
[GPS après déplacement](../../test-results/api-config-2026-10-18/final-gps-pan-free.png).
Les propriétés natives et sondages HTTP se trouvent dans le même dossier ignoré.

## J. Tests Flutter

Exécutés depuis `mobile/`, dernière passe :

- `dart format --output=none --set-exit-if-changed lib test` : 169 fichiers,
  aucun changement.
- `flutter analyze --no-pub` : aucune remarque.
- `flutter test --no-pub` : **523 tests réussis**, contre 491 avant cette tâche.
- Test supplémentaire de configuration : **3 réussis**, avec `API_BASE_URL`
  définie et les deux anciennes variables contradictoires vers `legacy.invalid`.
  Les sept sources utilisent exclusivement la base principale. Ces anciennes
  variables sont passées uniquement à ce test, jamais aux builds APK.

Les tests couvrent URLs invalides/absentes, slashs, préfixes, HTTP/HTTPS,
paramètres multiples, XYZ réels, extensions, versions, injection, authentification
limitée à l'hôte, installation répétée et réinstallation après vidage du style.
Les assertions métier préexistantes restent présentes.

## K. Backend

Aucun fichier backend changé par cette intervention : comparaison SHA-256 avec
la copie initiale. Les 864 tests du précédent chantier sont une référence
historique, pas une suite relancée ici. Vérifications réelles HTTP effectuées
sur les deux environnements ; aucun nouveau comportement backend à tester.

## L. Sécurité

Le fichier privé `mobile/.env.json` est identique octet pour octet à l'initial et
reste ignoré. Ses anciennes clés peuvent subsister sans effet sur le code.
Les APK sont construites avec une copie filtrée hors dépôt, en permissions 600.
Aucun secret de ce fichier n'est présent dans le delta de cette intervention.
Les tokens Firebase restent en mémoire pendant les sondages authentifiés ;
seule une empreinte de l'identifiant de session sert à comparer la restauration.
Aucun token, profil utilisateur ni attribut de signalement n'est recopié ici.

Mapbox reçoit le Bearer uniquement par `setCustomHeadersForHost`, pour l'hôte
validé du backend ; aucun en-tête global n'est introduit. Les tests vérifient
l'hôte unique et refusent une URL fournisseur absolue avant envoi du token.
Les fournisseurs marins restent appelés côté backend avec leurs propres headers.
Les règles d'authentification des signalements restent inchangées.

## M. Première revue

Lecture intégrale du delta par rapport à l'état initial et des deux nouveaux
tests. Corrections de cette passe : suppression du `?` final superflu pour une
URL sans paramètres, validation avant récupération du token Mapbox, échappement
des crédits HTML, corrections des remarques de l'analyseur. Les tests, formatage
et analyse statique ont été relancés après corrections.

## N. Deuxième revue

Seconde passe distincte du **même agent**, à partir des exigences initiales.
Contrôle de la source d'environnement unique, des appels applicatifs et de
chaque famille marine, de la conservation des paramètres et placeholders,
des règles de cache et des injections. Vérification du delta par empreintes :
aucun fichier initial manquant, backend inchangé, configuration privée inchangée,
aucune valeur privée détectée dans les fichiers de cette intervention.
La revue distingue compilation, sources installées, objets natifs réellement
rendus, services locaux manquants et routes distantes non déployées.

## O. Limitations

Le déploiement des routes marines sur le backend distant et les dépendances
applicatives locales restent nécessaires pour un environnement unique complet.
Le diagnostic local de carte n'est pas un remplacement du parcours applicatif.
L'ancienne APK restaurée à la demande de l'utilisateur ne constitue jamais une
preuve de la nouvelle configuration. Aucun déploiement n'a été demandé ou fait.

## P. État Git final

La branche et le HEAD restent identiques à l'initial. Le delta Git contient
32 fichiers suivis modifiés et 48 fichiers non suivis : il inclut les travaux
préexistants. Le delta propre à cette intervention contient les 15 fichiers
existants et les trois ajouts listés en D. Aucun fichier initial supprimé.
`git diff --check` : aucune erreur de whitespace. Aucun commit, push ou PR.

Preuves locales non versionnées : `test-results/api-config-2026-10-18/`
(sondages HTTP, journaux des tests et builds, propriétés natives, captures,
empreintes et comparaisons du delta). Les APK et journaux bruts privés restent
hors dépôt, sous `/tmp/nowave-api-config/`.
