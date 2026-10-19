# NoWave — deux connexions API directes

Recette du 19 octobre 2026, sur `feature/marine-bathymetry`, HEAD `d78f2563`.

## Résultat et configuration

L'APK installé sur le LGN LX1 utilise simultanément :

- `API_BASE_URL=https://api.no-wave.fr/` pour le backend principal ;
- `MARINE_API_BASE_URL=http://127.0.0.1:8004/` pour les données marines publiques.

`ApiConfig.marineBaseUrl` sélectionne la variable marine lorsqu'elle est non
vide. Une valeur absente, vide ou composée d'espaces conserve `API_BASE_URL`.
La valeur sélectionnée passe ensuite par les méthodes existantes `resolve`,
`endpoint`, `tileTemplate` et `withQueryParameters` : validation HTTP/HTTPS,
normalisation, préfixes, paramètres et placeholders sont conservés. Une URL
marine non vide mais invalide est refusée, sans repli silencieux.

La sélection se fait dans les sources publiques et leurs crédits. Aucun
intercepteur ne redirige globalement `/api/v1/map/`. `ApiService` et
`ReportTiles` conservent leur base principale. Les adresses explicitement
injectées dans les constructeurs restent prioritaires, notamment dans les
tests existants. Aucun `BATHYMETRY_TILES_URL` n'est réintroduit.

## Routes observées dans l'application

Les sept templates de sources ont été lus dans le style Mapbox natif après
installation. Le lien des crédits a également été vérifié dans les attributions.

| Route sous `/api/v1/map/` | Backend dans la recette | Format / version conservés |
|---|---|---|
| `bathymetry/{z}/{x}/{y}.png` | `http://127.0.0.1:8004/` | `png?v=coast-1` |
| `depth-contours/{z}/{x}/{y}.pbf` | local | `pbf?v=3` |
| `soundings/{z}/{x}/{y}.pbf` | local | `pbf?v=depths-4` |
| `underwater-hazards/{z}/{x}/{y}.pbf` | local | `pbf?v=3` |
| `seamarks/{z}/{x}/{y}.pbf` | local | `pbf`, paramètres inchangés |
| `port-infrastructure/{z}/{x}/{y}.pbf` | local | `pbf`, paramètres inchangés |
| `marine-sources` | local | lien HTML des crédits |
| `tiles/{z}/{x}/{y}.mvt` | `https://api.no-wave.fr/` | `mvt`, authentification conservée |

Profil, signalements, photos, alertes et autres routes métier restent sur le
backend principal. Firebase et Mapbox conservent leurs connexions existantes.

Preuves : `test-results/direct-api-2026-10-19/native-sources.json` et
`device-validation.json`. Les politiques de cache, seuils de zoom, filtres,
styles, images et slots des couches n'ont pas été modifiés.

## Authentification et absence de proxy requis

La source de signalements autorise uniquement l'hôte de `API_BASE_URL` avec
`setCustomHeadersForHost`. Aucun en-tête global n'est ajouté. Le SDK Android
installé compare exactement les hôtes ; dans la configuration testée,
`api.no-wave.fr` et `127.0.0.1` sont distincts. Les sources publiques ne demandent
pas de token et n'ajoutent pas d'en-tête d'authentification. Les tests contrôlent
que seul l'hôte principal reçoit l'en-tête des signalements.

Sur le téléphone, `ProfileService.getCurrentProfile()` a été appelé dans
l'application installée, avec son client et sa session existants. Sa base est
`https://api.no-wave.fr/` et la réponse HTTP réussie est décodée en `UserProfile`.
Le token est resté dans l'application ; aucune valeur de token ou donnée de
profil n'a été enregistrée dans les preuves. Les tests du client métier
vérifient également la conservation des en-têtes sur les appels authentifiés,
y compris les tuiles de signalements et une autre route sous `/api/v1/map/`.

Les six endpoints de tuiles publiques et les métadonnées ont répondu **HTTP 200
sans Authorization**, par connexion directe au serveur 8004. Le relevé des
connexions TCP pendant le chargement montre `adb` connecté directement au
processus backend préexistant, PID 457453, port 8004. Le reverse final est
uniquement `tcp:8004 tcp:8004`. Les réglages de proxy HTTP et PAC du téléphone
sont absents.

Aucun proxy HTTP n'a été démarré ni utilisé pour cette mission. Un ancien
processus `/tmp/nowave-proxy-8005.py` préexistait au travail ; il n'a pas été
modifié. Son ancien reverse USB 8005 a été retiré. Aucune URL de l'application
installée ni aucun contrôle HTTP de cette recette ne le cible. Le backend
marin 8004 et le backend distant n'ont pas été modifiés ou redémarrés.

## Fichiers de cette mission

| Fichier | Modification |
|---|---|
| `mobile/lib/core/api/api_config.dart` | Variable marine facultative et repli sur la base principale. |
| `mobile/lib/core/map/marine/marine_map_controller.dart` | Adresse par défaut du raster. |
| `mobile/lib/features/map/data/marine_tiles.dart` | Base des templates publics et du lien des crédits. |
| `mobile/lib/features/map/data/hydrography_layer.dart` | Defaults réseau des courbes, sondes et dangers. |
| `mobile/lib/features/map/data/buoy_layer.dart` | Defaults réseau des bouées et de la source commune aux aides fixes. |
| `mobile/lib/features/map/data/port_layer.dart` | Defaults réseau des infrastructures. |
| `mobile/test/core/api/api_config_test.dart` | Sélection facultative et validation commune. |
| `mobile/test/core/api/api_service_test.dart` | Base principale et en-têtes métier avec configuration marine active. |
| `mobile/test/features/map/data/api_sources_test.dart` | Sources réellement installées, routes, versions, crédits et hôte autorisé. |
| `mobile/.env.example.json` | Exemple facultatif vide, sans modifier `.env.json`. |
| `mobile/README.md` | Deux connexions, comportement de repli et commandes actuelles. |
| `docs/architecture/marine-sources.md` | Contrat réseau actuel. |
| Le présent rapport | Résultats et limites de recette. |

Les changements des fichiers de couches concernent leurs paramètres réseau ;
les définitions graphiques restent intactes. Aucun fichier backend, dépendance
ou configuration privée modifié.

## Tests et recette

| Contrôle | Résultat |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 177 fichiers, aucun changement requis |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | **534 tests passent** |
| Suite complète avec les deux adresses réelles | **534 tests passent** |
| Tests ciblés avec les deux adresses réelles | 45 tests passent |
| Tests ciblés : variable marine absente | 45 tests passent |
| Tests ciblés : variable vide | 45 tests passent |
| Tests ciblés : espaces seuls | 45 tests passent |
| Tests ciblés : préfixes, query parameters, slashs et espaces autour de la base | 45 tests passent |
| Tests API : variable marine invalide `ftp://...` | 42 tests passent, refus attendu de l'URL marine |
| Compilation et installation Android | Réussies, mise à jour sans effacer les données |
| Profil authentifié distant réel | Réponse réussie décodée en `UserProfile` |
| Six familles locales et métadonnées publiques | HTTP 200 sans token |

Les résultats bruts sont dans `test-results/direct-api-2026-10-19/`.

Captures réelles de l'APK à deux connexions :

- [Nuages à Z5,3](../../test-results/direct-api-2026-10-19/cloud-z5.3.png).
- [Carte marine à Z12](../../test-results/direct-api-2026-10-19/marine-z12.png) :
  isobathes, sondes, aides, infrastructures et signalement visibles.
- [Carte marine à Z14](../../test-results/direct-api-2026-10-19/marine-z14.png).
- [Recentrage GPS à Z15,5](../../test-results/direct-api-2026-10-19/gps-z15.5.png).

Les modifications locales préexistantes ont été comparées par SHA-256 avant et
après : **14 fichiers inchangés**, dont `.env.json`, `map_screen.dart`, les
composants/tests/textures/outils des nuages et le rapport de leur mission.
La photo de référence est inchangée. Les archives SHOM restent non suivies et
intactes. Les fichiers existants du globe satellite n'ont pas été modifiés.

## Deux passes de revue, même agent

**Revue 1 — code et tests.** Vérification de l'unique sélection marine,
du repli uniquement pour une valeur vide, de la réutilisation de la validation
et de la priorité des injections explicites. Contrôle des six familles,
des crédits et de la séparation des signalements. La matrice d'environnement
couvre également les préfixes et paramètres encodés. Les en-têtes et les tests
de session existants passent ; aucune règle graphique modifiée.

**Revue 2 — routes effectives et authentification.** Lecture des templates
installés dans Mapbox : six sources locales, signalements distants, crédits
locaux. Vérification du client réel de profil, du périmètre par hôte des
en-têtes Mapbox et de la connexion TCP directe `adb` → backend 8004. Contrôle des
captures Z5,3/Z12/Z14 et du GPS Z15,5. L'attribution des aides fixes réutilise
la source seamark ; elle suit donc la bonne base sans nouvelle configuration.
Les empreintes du travail des nuages et de la configuration privée concordent.
Aucun écart supplémentaire nécessitant une correction identifié. Ces deux
passes sont effectuées par le même agent, elles ne sont pas indépendantes.

## Commande exacte

Depuis `~/NoWave/mobile`, avec le backend marin déjà disponible sur le poste :

```bash
adb -s AV5PJV6328H03108 reverse tcp:8004 tcp:8004
flutter run -d AV5PJV6328H03108 --debug --no-pub \
  --dart-define-from-file=.env.json \
  --dart-define=API_BASE_URL=https://api.no-wave.fr/ \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/
```

L'APK validé a été construit avec :

```bash
flutter build apk --debug --no-pub --dart-define-from-file=.env.json \
  --dart-define=API_BASE_URL=https://api.no-wave.fr/ \
  --dart-define=MARINE_API_BASE_URL=http://127.0.0.1:8004/
```

La compilation utilise l'environnement privé pour les autres clés, sans le
modifier. Pour revenir au backend principal seul, compiler avec
`--dart-define=MARINE_API_BASE_URL=`. Le reverse USB 8004 est conservé pour
l'APK local installé ; il faut le rétablir après une reconnexion USB si ADB
l'a supprimé. Le réglage de veille USB du téléphone reste à sa valeur initiale 0.

## Limites et état Git

La disponibilité des fournisseurs de données en amont reste celle du backend
marin. La recette réelle concerne Android et une session utilisateur existante ;
aucune déconnexion ni nouvelle inscription imposée et pas de recette iOS dans
cette mission. `127.0.0.1` désigne le téléphone : le serveur local et le reverse
USB doivent rester disponibles pour cet APK.

Branche et HEAD inchangés : `feature/marine-bathymetry`, `d78f2563`. Index
inchangé. Aucun pull, reset, commit, push, changement de branche ou PR.
Les modifications des nuages restent présentes telles qu'elles étaient au
début. Listing complet : `test-results/direct-api-2026-10-19/git-final.txt`.
