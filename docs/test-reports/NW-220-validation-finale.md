# NW-220 — validation finale et commit local

21 octobre 2026. Validation du code local sur
`feature/NW-220-marine-zoom-persistence`, dans `/home/palms/NoWave-NW220`.
Les contrôles obligatoires décrits ci-dessous sont satisfaisants sur le parcours
testé. Le commit local est autorisé par la mission ; aucune publication n'est autorisée.

## Références et périmètre

- SHA de départ : `98711c18a8cf19aaf875bd740037e94f13790cbb`.
- Ticket [NW-220](https://linear.app/blueway/issue/NW-220/carte-marine-seuils-de-zoom-et-persistance-des-couches-z5z8z10z12z13)
  consulté en lecture seule : `In Progress`, mise à jour du 21 octobre à 17:04:21 UTC.
- Au démarrage : exactement **19 fichiers modifiés et 12 fichiers non suivis**,
  aucun changement indexé ni commit NW-220. Travail existant conservé.
- Décision explicite de l'utilisateur pendant cette reprise : **fondu linéaire
  des marques de Z10 à Z12**, 0 % à Z10, 50 % à Z11 et 100 % à Z12. Cette décision
  remplace leur invisibilité jusqu'à Z12 encore indiquée dans Linear. Aucun
  changement du ticket n'a été effectué.
- Au 21 octobre, cette reprise n'avait pas changé la palette, le satellite,
  l'océan ou l'atmosphère. Les corrections ultérieures du 22 octobre ont remplacé
  la palette bathymétrique et retiré satellite, nuages, Lune et textures du globe ;
  voir [le rapport de palette](NW-220-color-palette.md).
- Aucun rebase, merge, stash, nettoyage destructif, push, PR ou déploiement.
  Aucun travail effectué dans les autres worktrees. L'interpréteur Python du
  venv existant est réutilisé sans installation dans ce venv.

## Première passe — audit et corrections

Revue du diff backend/mobile, de l'encodeur GeoJSON, des normalisations et
providers, du contrôleur de viewport, des couches et interactions, des tests et
de chacun des douze fichiers initialement non suivis.

| Point | Résultat |
|---|---|
| Identités et géométries | Courbes découpées sur grille Z12 fixe ; identité source conservée ; demi-bords à propriétaire unique ; coordonnées WGS84 non remplacées au zoom |
| Persistance | Courbes indépendantes des étiquettes et sans extinction à Z15 ; enrichissement par union d'identités ; ports retenus avant les nouveaux candidats |
| Limites de zoom | Raster Z5 ; ports préparés Z6, visibles Z8, enrichis Z10 ; profondeurs préparées Z12 et visibles Z13 ; sondes disponibles jusqu'à leur résolution Z16 |
| Marques | Expression commune de fondu pour bouées, balises, phares, feux et dangers ; accès par appui long adapté au nouveau seuil ; règles IALA, classifications et PNG conservés |
| Placement à Z10 | Données réellement téléchargées mais sources de placement des marques vides à Z10 et en dessous ; elles ne réservent pas de collisions lors du préchargement stabilisé |
| Diagnostics | Correction d'une accumulation des anciennes erreurs dégradées après déplacement ; erreurs et temporisations limitées aux cellules actuellement demandées |
| Quota du proxy | Correction des routes GeoJSON qui tombaient dans le quota de l'API générale ; seules les cinq familles XYZ exactes rejoignent le quota marin |
| Garde-fous | Deux requêtes client simultanées ; caches et taille des réponses bornés ; annulation et reprise ; erreurs jamais transformées en réponses vides réussies ; séparation des services publics et authentifiés |

Deux régressions ont été reproduites avant correction : le test des diagnostics
observait **18 anciennes erreurs au lieu de 9** au second déplacement ; la vraie
sonde Nginx observait **14 réponses 429 sur 45 snapshots et un profil en 429**.
Les mêmes contrôles passent après correction, sans neutraliser leurs assertions.
Les assertions existantes sur le rééchantillonnage, le contraste et la saturation
du raster sont conservées.

## Deuxième passe — vérifications indépendantes

Python 3.14.4, dépendances pip déjà présentes dans le venv du dépôt :
pytest 9.0.3, Ruff 0.16.8, FastAPI 0.141.1, Shapely 2.1.2. Les dépendances sont
décrites par `backend/requirements*.txt` ; la configuration pytest/Ruff est dans
`pyproject.toml`. Flutter 3.47.6, Dart 3.13.5.

| Contrôle | Résultat |
|---|---|
| Format des 16 fichiers Dart concernés | 0 changement au contrôle final |
| `flutter analyze --no-pub` | Aucun problème |
| Sept fichiers de tests Flutter demandés | 36 tests réussis |
| `flutter test --no-pub --reporter expanded` | **719 tests réussis**, aucun échec |
| `python -m ruff check .` | Réussi |
| Suite backend API + unit complète | **975 tests réussis, 1 ignoré**, aucun échec |
| Sonde native Nginx, cache réel et fournisseur synthétique local | 45 snapshots GeoJSON servis, profil protégé et disponible ; protection contre abus toujours vérifiée |
| APK debug | Compilation réussie ; APK construite et installée identiques par SHA-256 |
| Diff, secrets, fichiers temporaires | `git diff --check` propre ; recherche des valeurs privées et motifs de credentials sans résultat ; artefacts exclus |

Le seul test ignoré nécessite les archives SHOM XYZ locales, absentes et hors
sources de sondes MVP. La suite séparée de tests PostgreSQL n'a pas été lancée :
aucun changement de base ni de repository de données dans ce ticket. Un
avertissement Starlette/httpx subsiste dans les tests. Les avertissements KGP
de compilation ne font pas échouer l'APK.

Pour exécuter les vrais tests Compose et Nginx sous WSL, les binaires Ubuntu ont
été extraits sous `/tmp/nw220-docker` et `/tmp/nw220-nginx`, sans démarrage de
daemon Docker, installation globale ni modification du VPS. Commande finale :

```bash
PATH=/tmp/nw220-docker/root/usr/bin:$PATH \
DOCKER_CONFIG=/tmp/nw220-docker/config \
NOWAVE_TEST_NGINX=/tmp/nw220-nginx/root/usr/sbin/nginx \
/home/palms/NoWave/.venv/bin/python -m pytest -q -rs
```

## Validation réelle Android

Téléphone physique **LGN LX1, Android 15 / API 35**, détecté par Flutter et ADB
après reconnexion. Application réelle `lib/main.dart`, compte et GPS conservés.
Aucune désinstallation, purge de données, localisation simulée ou création de
signalement. L'environnement privé existant reste inchangé ; seule la valeur
`MARINE_API_BASE_URL=http://127.0.0.1:8004/` est surchargée au lancement, avec
`adb reverse tcp:8004 tcp:8004`. Le backend métier reste celui de production.

- **38 captures aller-retour** entre Z4,99 et Z18, dont Z5, Z10, Z11, Z12,
  Z12,99, Z13 et Z14. Aucun rendu sous les seuils des symboles/profondeurs,
  aucune erreur de requête marine dans cette matrice. Captures réellement
  examinées : raster absent à Z4,99 et présent à Z5 ; marques atténuées à Z11
  et opaques à Z12 ; absence des profondeurs à Z12,99 puis présence à Z13.
- **20 vues de sécurité** : cardinales fixes et flottantes N/E/S/O et dangers
  isolés fixes et flottants à Z12 et Z16. Comparaison des identités projetées
  dans l'écran avec les requêtes natives de rendu : aucun prioritaire manquant.
- La preuve flottante manquante de la première phase est maintenant réalisée :
  bouée SHOM **BASSE DES RENARDS**, `shom:boyisd:FR000006114900001`, à
  `-4.7913148 / 48.350016`, réellement rendue à Z12 et Z16. Captures examinées.
- Ports Saint-Mandrier Z8/9/10/12/14/16/18 : aucun représentant initial encore
  dans le champ ne disparaît ; conservation des identités de sélection.
- Trois véritables isobathes EMODnet **50/100/200 m** suivies à Z13/14/15/16/18 :
  rendues à chaque palier, une seule empreinte de géométrie par identité.
- Déplacements rapides, retour sur zone, rotation 90°, inclinaison 60° et
  rechargement du style : la courbe suivie reste tracée.
- Marseille Z14 retesté sans erreur courante. Deux tuiles Open Waters près de
  Brest ont d'abord produit des 503, les marques SHOM restant disponibles.
  Nouvelle tentative HTTP, puis retour dans l'application : **reprise réelle
  sans erreur courante et bouée toujours rendue** ; aucun faux succès vide.
- Trois cycles supplémentaires Z12 → Z13 → Z14 → Z13 passent sans erreur.
  45 snapshots à chaque fin de cycle, budgets respectés ; tas Dart
  **116 955 568 → 123 259 520 → 117 071 536 octets**. Pas d'accumulation évidente
  sur ce parcours. Après la longue série : PSS Android 698 139 Ko, RSS 743 320 Ko.
- Des avertissements de réflexion Java Mapbox apparaissent au démarrage ;
  l'application poursuit son fonctionnement et les contrôles natifs passent.
  Aucune exception Flutter non gérée ni rejet d'expression de style observé.

APK testée : `e090d02b2a7940ea350482aec278e6c84485882a68407a485f304066d41dc1d3`.
Empreinte du code, tests, outils et configuration Nginx :
`f55d26fab0af583d051d30b6fdd22715a73b1ee92ad654d6718e2787d8d524e3`.

## Limites et risques résiduels

Les fournisseurs publics peuvent être momentanément indisponibles ; la reprise
observée ne garantit pas leur disponibilité future. Les caches et le voisinage
bornés ne promettent pas une couverture exhaustive ni un mode hors ligne illimité.
Les changements de résolution peuvent refaire des requêtes de snapshots : les
cycles mesurés ajoutent 150 requêtes par cycle de quatre paliers, sans nouveau
téléchargement de courbes conservées, avec concurrence client bornée à deux.
Ce parcours debug ne constitue pas un benchmark release/FPS comparé à `dev`.

À Brest, SHOM « BASSE DES RENARDS » et Open Waters « Les Renards » publient deux
identités proches avec des noms différents. La fusion conservatrice existante
les garde : leur superposition n'est pas un doublon ajouté pour une même identité
par le client. Aucune fusion par simple proximité ou classification inventée.
Le cas exact d'un signalement NoWave superposé à un symbole de sécurité n'a pas
été fabriqué ; les tests des signalements restent verts. L'appui long et les
crédits ont aussi des preuves physiques dans la première phase archivée.
Les courbes généralisées conservées ne sont pas des levés de précision portuaire.

## Fichiers examinés et sélection pour le commit

Les douze fichiers initialement non suivis ont été lus individuellement :

| Fichier | Rôle / décision |
|---|---|
| `backend/app/infrastructure/marine/viewport_encoding.py` | Encodeur nécessaire au rendu persistant ; inclus |
| `backend/tests/unit/test_marine_viewport.py` | Régressions géographiques, routes, annulation et format ; inclus |
| `docs/architecture/marine-zoom-persistence.md` | Contrat technique mis à jour ; inclus |
| `docs/test-reports/NW-220-prepublication.md` | Archive des premières preuves, explicitement signalée comme historique ; incluse |
| `mobile/lib/core/map/marine/marine_zoom.dart` | Seuils et expression du fondu communs ; inclus |
| `mobile/lib/features/map/data/marine_debug.dart` | Instrumentation VM de la vraie carte, limitée à `kDebugMode` ; incluse |
| `mobile/lib/features/map/data/marine_viewport.dart` | Contrôleur réseau, cache, persistance et sélection ; inclus |
| `mobile/test/features/map/data/marine_viewport_test.dart` | Régressions du contrôleur, notamment diagnostic borné et placement à Z10 ; inclus |
| `mobile/tool/nw220_device_validation.py` | Matrice ADB/VM réelle, avec palier Z11 ajouté ; inclus |
| `mobile/tool/nw220_extra_validation.py` | Parcours complémentaires, étape de fondu renommée ; inclus |
| `mobile/tool/nw220_final_validation.py` | Relecture des cibles réelles et diagnostics Android ; inclus |
| `mobile/tool/nw220_vm.py` | Pilote VM manuel ; inclus |

Ces outils sont des outils manuels de validation pour l'appareil et le port VM
indiqués dans leur source ; ils nécessitent `websockets`, ADB, le log d'une vraie
session Flutter et, pour le parcours de sécurité historique, le fichier local
`test-results/NW-220/safety-targets.json`. Les preuves ne sont pas des fixtures
injectées dans l'application.

La sélection comprend ces douze fichiers, les 19 fichiers initialement modifiés,
les trois fichiers nécessaires à la correction du quota Nginx et ce nouveau
rapport : **35 fichiers**. La liste exhaustive est enregistrée localement dans
`test-results/NW-220/final-validation/commit-files.json`.

Exclus : `.env.json`, clés, APK, captures, logs, bases/cache, scripts ponctuels
de cette reprise et binaires extraits sous `/tmp`. Les preuves locales restent
dans le dossier ignoré `test-results/NW-220/final-validation/` : logs des tests,
manifestes, `matrix-proof.json`, `regressions-proof.json`, `apk-proof.json`,
`brest-recovered.json`, `memory-cycles.json` et captures natives.

## État Git et conclusion

Message du commit local autorisé :
`fix(NW-220): persist marine layers across zoom levels`.
Le SHA final est fourni dans le compte rendu final et dans la preuve locale
`test-results/NW-220/final-validation/git-final.json` ; ce rapport fait lui-même
partie du commit. Branche NW-220 conservée ; index et worktree doivent être
propres après ce commit. Aucun push, aucune PR, aucune écriture Linear.

**Validation préalable au commit local satisfaisante sur les contrôles requis
et le parcours Android décrit, avec les limites explicites ci-dessus.**
