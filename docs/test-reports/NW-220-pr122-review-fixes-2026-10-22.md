# NW-220 — corrections locales après revue de la PR #122

## A. État Git initial

- Dépôt et worktree de la branche PR : `/home/palms/NoWave`, `feature/NW-220-satellite-bathymetry-colors`.
- HEAD initial et SHA GitHub de la PR : `0e43c6deff9967c4494c0ddbac5a0e12b57d3d39`. Index et worktree propres ; aucun commit après le SHA examiné.
- `origin/dev` : `65d483c780448ad42c03a0e682cb757c7654f551`. La branche PR contient les trois commits NW-220 et le merge préalable de `dev` ; aucune nouvelle divergence locale au départ.
- Le worktree distinct `/home/palms/NoWave-NW220-backend`, branche `fix/NW-220-backend-production`, a seulement été identifié. Il n'a pas été modifié.

## B. Premier audit : famine de chargement

`MarineViewport.schedule()` annulait son timer de 200 ms à chaque événement caméra. Une série d'événements espacés de moins de 200 ms pouvait donc empêcher indéfiniment `synchronize()` de démarrer. Chaque événement incrémentait aussi `_revision` et fermait tous les clients dans `_active`, y compris les cellules encore utiles. `_fetch()` rejetait une réponse si la révision avait changé, sans vérifier si sa cellule restait demandée. Enfin, `synchronize()` gardait `_busy` pendant le drainage séquentiel de toutes les cellules : une requête lente retardait la prise en compte d'une nouvelle zone.

Le test de cinq secondes ajouté dans le dépôt reproduit la condition de famine de l'ancien debounce : événement toutes les 40 ms, rotation continue et changement de zone à mi-parcours. La version corrigée charge et injecte des ports pendant le mouvement. Le test temporaire cité par la revue n'était pas disponible et n'est pas présenté comme exécuté.

## C. Deuxième audit indépendant

Lecture séparée du chemin caméra → Mapbox → viewport → HTTP → GeoJSON → source native :

- Les changements de bearing et de pitch n'impliquent pas de nouvelle identité de cellule XYZ. Leur annulation systématique était abusive.
- Un pan géographique peut rendre une cellule inutile ; l'annulation doit suivre le nouvel ensemble `_wanted`, non le numéro d'événement caméra.
- Une réponse tardive reste valable si sa cellule est encore demandée. Une réponse après annulation ou sortie de zone ne doit pas remplir le cache ni la source.
- Le rendu doit être invalidé séparément des requêtes : un changement de caméra ou de style peut rendre une écriture native obsolète sans rendre le résultat HTTP inutile.
- La pause, la destruction du contrôleur et le rechargement du style réclament des vérifications distinctes des événements de mouvement.

Ces constats confirment le premier diagnostic et ajoutent le risque de rendu natif obsolète après changement de style.

## D. Correctif P0

- Planification immédiate au premier événement valide, puis coalescence à une synchronisation au plus toutes les 200 ms pendant le mouvement. Le timer n'est plus repoussé à chaque image.
- Recalcul de `_wanted` et annulation ciblée des cellules devenues inutiles. Bearing et pitch seuls ne ferment plus les requêtes.
- Drainage réseau séparé du calcul du viewport ; deux travailleurs au maximum consultent dynamiquement `_wanted`. Les nouvelles cellules peuvent être prises en compte alors que les anciennes requêtes sont encore en vol.
- Validation des réponses par état du contrôleur, annulation effective et appartenance actuelle à `_wanted`, sans dépendance à une révision caméra.
- Coalescence du rendu des sources en un seul travail en cours et une relance sur l'état le plus récent, avec une révision de rendu propre à la caméra et au style. Les réponses acceptées sont injectées pendant le mouvement, sans file de rendus illimitée ; une ancienne écriture ne marque pas le nouveau style comme à jour.
- `pause()`, `resume()`, `dispose()`, le backoff, le plafond de 64 snapshots et 12 MiB, les identités retenues et les courbes fixes Z12 restent en place.

## E. Tests du mouvement

Les tests de [marine_viewport_test.dart](../../mobile/test/features/map/data/marine_viewport_test.dart) couvrent : viewport fixe et cache, cinq secondes de mouvement continu, rotation sans déplacement, pan et annulation, réponse tardive encore utile, réponse tardive devenue inutile, rechargement du style, HTTP 503, timeout, reprise, courbes persistantes, pause et destruction. Les sources GeoJSON enregistrées par le faux style sont contrôlées, en plus des compteurs HTTP.

Dans la simulation de cinq secondes : 125 événements environ, 18 requêtes (neuf cellules dans chacune des deux zones), zéro annulation sur rotation, deux requêtes simultanées au maximum, ports présents dans la source avant la fin du mouvement. Les autres tests vérifient deux annulations lors d'un pan hors zone et l'absence de mise en cache des réponses obsolètes. Ces mesures proviennent d'un transport HTTP factice ; elles ne représentent pas le débit réel d'un bateau.

## F. Cache bathymétrique P1

`BathymetryTileCache.VERSION` passe de `coast-feather-2` à `marine-palette-3`, en accord avec l'URL Flutter et la recolorisation PNG du producteur EMODnet. Un test insère une ancienne clé disque, vérifie le nouveau rendu et sa réutilisation mémoire, et confirme que l'ancienne entrée n'est ni utilisée ni purgée. Les plafonds 32 MiB mémoire / 128 MiB disque, TTL 86400 s, file 128 et partage des requêtes restent inchangés. Aucun cache de production n'a été touché.

## G. Marques marines

Le code conserve l'interpolation linéaire `['interpolate', ['linear'], ['zoom'], 10, 0, 12, 1]`, soit 0 %, 25 %, 50 %, 75 % et 100 % à Z10, Z10.5, Z11, Z11.5 et Z12. Le préchargement à Z10 laisse les sources de rendu vides à Z10, afin qu'une icône transparente ne réserve pas de place. Les couches prioritaires des cardinales et dangers isolés conservent `iconAllowOverlap` à Z12 et au-delà ; les tests de bouées et d'aides fixes restent dans la validation. Aucun changement de classification IALA ou des pictogrammes n'a été fait.

## H. Charge NOAA

Mesure locale bornée avec `MarineHTTP` et un `MockTransport` qui renvoie des couvertures vides, pour neuf cellules autour de Miami à chaque palier et deux demandes client simultanées : Z11→Z12 déclenche 45 requêtes de couverture ; Z12→Z13 en déclenche 45 autres. Pic fournisseur observé : quatre requêtes simultanées, borne du client HTTP non persistant. Réponses factices : 3 780 octets au total ; snapshots : 378 octets par palier ; aucune sonde, aucun échec ; latences locales 254 ms et 274 ms. Ces chiffres sont propres au faux fournisseur, sans trafic NOAA réel : ils ne mesurent pas le volume, le taux de cache ni la latence des données réelles. Les sondes NOAA restent géographiquement réservées à la couverture NOAA, sans repli automatique depuis EMODnet. Le nombre de requêtes de couverture à Z12/Z13 reste un risque à surveiller en recette réelle.

## I. Documentation et outils

Les liens vers les fichiers de code réellement versionnés dans [l'archive de prépublication](NW-220-prepublication.md) sont devenus relatifs au dépôt. Les anciens liens absolus vers `test-results/` ignoré ont été remplacés par leurs noms d'artefacts locaux, avec une indication explicite de leur indisponibilité sur GitHub. Aucun fichier de preuve non vérifié ou secret n'a été ajouté. Les outils NW-220 de validation manuelle sont conservés. La prochaine mise à jour autorisée de la PR devrait mentionner explicitement la suppression validée des nuages, de la Lune et des textures du globe.

## J. Première validation

- `dart format` sur les fichiers modifiés puis `flutter analyze --no-pub` : aucune anomalie.
- `flutter test --no-pub --reporter compact` : **800 tests réussis**. Les nouveaux tests du viewport comprennent le mouvement de cinq secondes, réponses tardives, pan, cycle de vie, timeout et reconnexion.
- Tests ciblés Flutter du viewport, des marques, des seuils et de l'hydrographie : **36 tests réussis**.
- Tests backend ciblés : **27 réussis**, avec un avertissement de dépréciation Starlette/httpx ; Ruff ciblé : réussi.
- Suite backend hors deux tests Compose dépendant de Docker Desktop absent de ce WSL : **992 réussis, 2 ignorés, 2 exclus**, un avertissement Starlette/httpx. Ces deux tests Compose échouaient déjà avant la mission pour l'environnement Docker ; aucun test n'a été supprimé ni affaibli.

## K. Deuxième validation

La seconde relecture du diff a séparé la révision des requêtes de celle du rendu. Elle a ajouté une garde après l'écriture asynchrone de la source native : une écriture commencée avant un rechargement de style ne doit pas marquer ce nouveau style comme déjà rempli. Elle a aussi remplacé la chaîne potentiellement croissante des rendus par une unique opération en cours et une relance coalescée, et vérifié que les erreurs transitoires du drainage réseau sont observées sans devenir une erreur non capturée d'un appel planifié. Les tests ciblés ont été relancés après ces ajustements.

Résultats après ces ajustements : formatage des 226 fichiers `lib` et `test` propre, `flutter analyze --no-pub` sans anomalie, **36 tests Flutter ciblés réussis**, Ruff ciblé réussi et **41 tests backend ciblés réussis** (un avertissement de dépréciation Starlette/httpx).
Après la dernière simplification de la file de rendu, l'analyse Flutter et le test complet du contrôleur viewport ont de nouveau réussi.

Points contrôlés : deux travailleurs HTTP au maximum, neuf cellules par famille, cache 64 snapshots / 12 MiB, points retenus 4 MiB, annulation sur sortie de zone seulement, timers de caméra et de retry annulés lors de la pause, réponses refusées après `dispose()`, identités et géométries des courbes fixes Z12, aucune modification de la flèche GPS, des signalements ou des règles de déploiement. Le test Android de pan retour et reload complète ce contrôle. Les comptes réseau pendant la rotation sont stables une fois les cellules remplies ; aucun appel par image Mapbox.

## L. Android

LGN LX1, Android 15, détecté via ADB Wi-Fi `10.6.2.48:42937` et `flutter devices`. API locale compatible lancée sur `127.0.0.1:8006` avec cache isolé dans `test-results/NW-220-pr122-review/` ; redirection ADB `tcp:8006`. L'APK debug utilise une définition Flutter temporaire `MARINE_API_BASE_URL=http://127.0.0.1:8006`, sans modification de `.env.json`.

La vraie application `lib/main.dart` a été compilée et installée. Après une première erreur de récupération du profil, le bouton **Réessayer** a ouvert la carte normale ; aucun profil ni donnée de compte n'a été modifié.

- Z9 Marseille : neuf cellules en cache, 145 ports dans les données, dix ports réellement rendus après stabilisation.
- Mouvement déterministe continu dans l'application réelle : 32 changements de caméra en **9,37 s**, longitude 5,93→6,73 et bearing croissant. Les requêtes passent de 17 à 20 avant la fin ; des ports restent rendus au milieu et à la fin. Aucune nouvelle annulation n'est observée pendant ce parcours ; les 20 requêtes comprennent le chargement initial, et l'unique annulation précède le parcours. Ce test n'est pas un trajet GPS réel.
- Canoubier avec données SHOM réelles via le backend local : présent en données mais absent du rendu à Z10 ; rendu à Z10.5, 11, 11.5, 12 et 16. Le style natif porte `icon-opacity = interpolate(linear, zoom, 10, 0, 12, 1)` sur les couches de marques contrôlées ; les couches cardinales et dangers isolés ont `icon-allow-overlap = true`.
- À Z12, 26 courbes sont préchargées à Saint-Mandrier sans couche de profondeur rendue. À Z13, les lignes, étiquettes et sondes apparaissent. Les 26 identifiants et géométries de Z13 sont identiques à Z14, Z15, Z16, après pan retour et après reload du style. Les captures Z12 pour Canoubier et Z13 pour la profondeur ont été inspectées.
- La matrice atteint 45 snapshots au maximum dans ce parcours et moins de 1 MiB de cache encodé sur les points mesurés. Le diagnostic Android `dumpsys meminfo` indique 788 107 KiB de PSS pour cette exécution debug ; sans mesure témoin ni version release, ce chiffre n'est pas un budget de production.

Preuves locales non versionnées : `test-results/NW-220-pr122-review/android-continuous.json`, `android-matrix/summary.json`, `android-matrix/native-style.json`, JSON détaillés et quatre captures PNG. Le backend était local ; **ceci ne valide pas `api.no-wave.fr`**, dont les routes GeoJSON peuvent encore répondre 404.

Le serveur local a signalé ponctuellement `Bathymetry disk cache unavailable` durant cette recette ; les réponses bathymétriques observées étaient 200, mais la persistance disque sous charge n'est pas validée par ce parcours. Après la recette, l'APK debug a été reconstruite avec `MARINE_API_BASE_URL=` (SHA-256 `466bf156034cab7136f6ca2ed73e5701602432993cfec6193fa9414ecea51861`), réinstallée avec succès et relancée. Le reverse ADB `tcp:8006` a été retiré et le serveur local arrêté. Aucun chemin ou hôte local n'a été inscrit dans `.env.json` ou un autre fichier suivi.

## M. État Git final

Six fichiers locaux concernés : `marine_viewport.dart`, son test, `bathymetry_cache.py`, son test, l'archive documentaire de prépublication et le présent rapport. HEAD reste `0e43c6d`. Aucun commit, push, merge vers `dev`, changement Linear, modification de PR ou déploiement dans cette mission. Le worktree backend distinct est intact. `git diff --check` est propre.
La PR GitHub ouverte pointe toujours sur `0e43c6deff9967c4494c0ddbac5a0e12b57d3d39`. Diff suivi : 546 lignes ajoutées et 135 supprimées sur cinq fichiers ; le présent rapport non suivi compte 99 lignes supplémentaires.

## N. Verdict

**PR #122 — PRÊTE POUR NOUVELLE REVUE.** Les deux anomalies de code signalées sont corrigées localement et démontrées par tests automatisés et recette Android avec backend local. Cette conclusion concerne la revue du correctif dans le worktree : la PR distante n'inclut pas encore les changements, puisqu'aucune publication n'est autorisée. Les routes GeoJSON et tuiles bathymétriques de production, la charge NOAA réelle et les deux tests Compose sans Docker restent des limites explicites avant toute décision de fusion ou de mise en production.
