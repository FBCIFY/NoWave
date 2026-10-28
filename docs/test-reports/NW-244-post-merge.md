# NW-244 — Correctifs après fusion de la PR #131, 23 octobre 2026

## A. État Git initial

- Dépôt `FBCIFY/NoWave`, `origin/dev` vérifié après fetch : `ec0e12e1b707ea7967f2b4059adf25587a231f26`.
- [PR #131](https://github.com/FBCIFY/NoWave/pull/131) fermée et fusionnée le 23 octobre 2026 à 21:47, heure de Paris. Le code web est identique entre son commit source `d7cf9afc` et la fusion ; la branche corrective part de la fusion, avec la PR #130 et tous les changements de `dev`.
- [CI de fusion 40014142351](https://github.com/FBCIFY/NoWave/actions/runs/40014142351) : Python, PostGIS, Web, Admin Web, Flutter, audits et déploiement de fusion finalement réussis. Ce déploiement est antérieur aux opérations de correction ; aucune action de production n'a été déclenchée par cette mission.
- Worktree original sur `feature/admin-maritime-surveillance-ui`, HEAD `d7cf9afc`, avec les répertoires non suivis `docs/design/`, `mobile/codex_photo/`, `vps/`, laissés intacts.
- Worktree correctif `/home/palms/NoWave-NW244`, branche neuve `fix/NW-244-post-merge-surveillance`, créée depuis `origin/dev` ; propre à sa création.
- Les pushes sur une branche corrective ne déclenchent pas le workflow. Une PR vers `dev` exécute les contrôles et audits ; le déploiement exige `event_name == push` ET `refs/heads/dev`. Aucun déclencheur ni garde de déploiement n'est modifié.

## B. Diagnostic

| Priorité | Défaut reproduit | Cause |
|---|---|---|
| P1 | Aucun accès aux signalements 21 et suivants | Frontend sans page, SQL limité à 20 sans indication de suite |
| P2 | Réponses périmées possibles dans les listes, la carte et une même fiche réouverte | L'annulation seule ne garantit pas l'ordre des réponses ; garde de fiche limitée à l'identifiant |
| P2 | Dominante terrestre beige/jaune | Fond `#c8bc9f`, relief `#E2CCA0` et ombres brunes |
| P2 | Promesse erronée d'exhaustivité après zoom | Message de troncature ambigu malgré un lookahead SQL déjà correct |
| P2 | Catégorie non reconnue invisible | Nom d'image calculé sans image de secours |
| P2 | Fiche directe dépendante du chargement Mapbox | Lecture de la fiche déclenchée uniquement par `map.load` |
| P2 | Commandes et panneaux se recouvrant | Panneau droit au-dessus de « Vue Atlantique » ; deux panneaux sur mobile |

## C. Corrections

| Fichier / fonction | Modification et effet | Risque / protection |
|---|---|---|
| `backend/app/infrastructure/repositories/postgresql_admin_read_repository.py`, `user_reports` | 21 lignes lues, 20 retournées avec `has_more` ; `page_offset` valide la borne ; ordre observation/UUID inchangé | Contrat adapté avec sa route ; SQL réel et pages limites testés |
| Même fichier, `map_reports` | Plafond interne de 1 000 même si un appelant fournit une limite supérieure | Le lookahead existant est conservé ; seuils et ordre vérifiés sur PostGIS |
| `backend/app/web/routes/admin_pages.py`, `map_user_reports` | Ajout JSON `has_more` sans requête de comptage | Session active, UUID, bornes de page et `no-store` inchangés |
| `backend/app/web/static/surveillance.js`, `loadUserReports`, `resetUserReports` | Pagination, chargement, vide, fin, réessai, session expirée ; contrôleurs et identité de requête ; reset à chaque sélection/recherche/fermeture | Tests DOM avec transport ignorant l'annulation et tests clavier Chromium |
| Même fichier, `loadUsers`, `loadReports`, `selectReport` | Garde contre réponses tardives, y compris même identifiant ; fiche directe indépendante de Mapbox ; sélection mémorisée jusqu'à création de la source | Tests DOM, liens directs et sélection réelle Mapbox |
| `maritime-style.js`, `apply` | Palette terrestre froide uniquement | Géométrie, eau, GEBCO, sources et zooms préservés et testés |
| `marker-icons.js`, `install`, et couches de `surveillance.js` | Image neutre et expression `coalesce(image(...), image(report-unknown))` ; cercles si installation canvas impossible | Couleurs/formes des trois catégories intactes ; propriétés canvas et rendu natif vérifiés |
| `admin.css`, panneaux/en-tête mobile | Commandes dégagées, entête compact et un panneau à la fois sur mobile | Dimensions, absence de débordement et actions tactiles testées à 390×844 |
| `.github/workflows/checks.yml`, Admin Web/PostGIS | Tous les tests Node et 26 parcours Chromium avec vraie base isolée ; audit npm et preuves jointes | Aucun contrôle existant supprimé ; Firebase/Mapbox simulés dans la CI déterministe |
| `backend/tests/{api,database,web,browser}` | Régressions API, SQL réel, DOM et navigateur, fixtures isolées, dépendance Playwright verrouillée | Serveur de recette hors application, loopback uniquement, base aléatoire supprimée à l'arrêt |

## D. Palette cartographique

- Fond terrestre `#354b60` ; bois `#344f58`, broussailles `#48616b`, herbe `#566e79`, cultures `#657b87`, neige `#c7d5df`.
- Relief : ombre `#263d52`, lumière `#91a9bb`, opacité 0,4.
- Eau `#002D51`, trait côtier `#d8e4ed` fin : inchangés.
- Animaux `#06B6D4`, obstacles `#F97316`, pollution `#7C3AED` : couleurs, chemins canvas, ratio 2, centre `(24,28)` et ancrage central conservés. Secours `#64748B`.
- Clusters `#cf3149`, halo `#e64255`, compteurs blancs, sélection après les clusters : inchangés.
- Landcover et relief restent sous l'eau ; raster après l'eau ; trait côtier puis signalements au-dessus. Source GEBCO `gebco-2026-v2`, Z6 natif, disparition Z6–Z8, sans filtre, fichiers et géométrie inchangés.

## E. Pagination et limite cartographique

| Nombre | Pages réellement parcourues | Résultat |
|---:|---|---|
| 0 | 0 résultat en page 1 | « Aucun signalement », suivant désactivé |
| 1 | 1 | Un lien, fin |
| 20 | 20 | Une page, fin |
| 21 | 20 + 1 | 21e lien suivi jusqu'à sa fiche réelle en navigateur |
| 40 | 20 + 20 | Deux pages, fin |
| 41 | 20 + 20 + 1 | Trois pages, fin |

Les six seuils sont couverts séparément en API, SQL réel, DOM simulé et Chromium bureau/mobile. Page inexistante : tableau vide, pas de suite, retour disponible si page > 1. Changement d'utilisateur, fermeture/réouverture, pages en cours, réponses inversées, boutons désactivés, erreurs réseau/HTTP et expiration sont couverts.

| Points dans l'emprise | Points retournés | `truncated` |
|---:|---:|---|
| 999 | 999 | false |
| 1 000 | 1 000 | false |
| 1 001 | 1 000 | true |

Tests sur PostgreSQL/PostGIS réel : coordonnées exactes, UUID de départage, ordre stable répété, limite supérieure impossible à contourner et nouvelle emprise après zoom. Le texte précise que seuls les signalements chargés sont comptés, sans garantir qu'un zoom suffise. Décision MVP validée, sans agrégation serveur exhaustive.

## F. Tests locaux

Environnement Python de référence : CPython 3.12.15 avec les versions verrouillées (dont FastAPI 0.141.1 et Pillow 13.0.0). Base Docker dédiée `nowave-nw244-test`, PostgreSQL 17/PostGIS, port 55433, aucune base réelle utilisée.

| Commande | Réussis | Échoués | Ignorés |
|---|---:|---:|---:|
| `python -m pytest backend/tests/api backend/tests/unit -q` | 1 153 | 0 | 2 |
| `python -m pytest backend/tests/database -q` | 286 | 0 | 0 |
| `python -m pytest backend/tests/api/test_admin_surveillance.py backend/tests/database/test_admin_read_repository.py -q` | 32 | 0 | 0 |
| `node --test backend/tests/web/*.cjs` | 23 | 0 | 0 |
| `npm test --prefix backend/tests/browser` avec configuration Mapbox explicite | 28 | 0 | 0 |

Les 2 tests Python ignorés concernent les archives locales SHOM XYZ absentes et la sonde Nginx native opt-in. `git diff --check`, Ruff et les cinq `node --check` sont également exécutés. Les 64 tests admin API/Web/SQL de démarrage avaient réussi avant extension de la couverture. Ces exécutions se recouvrent et ne doivent pas être additionnées comme tests uniques.

Une première tentative sous Python 3.14 s'est interrompue par segmentation dans le test de cache colorimétrique multithread `test_emodnet_bathymetry.py` ; elle n'est pas comptée comme une suite verte. La suite complète a ensuite réussi sous la version Python 3.12 prévue par la CI. Aucune modification de ces composants ni diminution de leurs assertions.

Ce rapport est versionné avant publication. Les résultats GitHub Actions du nouveau commit sont rapportés séparément dans la nouvelle PR, Linear et le compte rendu final ; les résultats locaux et l'ancienne CI ne servent pas de preuve pour cette nouvelle exécution.

## G. Recette navigateur

- Chromium 153.0.8010.12 via Playwright 1.64.1, Linux, HTTPS local, 1440×1000 et 390×844 tactile.
- `admin.spec.cjs` : 26 scénarios bureau/mobile avec vraie application, session et modération, base isolée ; frontières Firebase, Mapbox et stockage photo simulées.
- `mapbox.spec.cjs` : 2 parcours avec **Mapbox GL JS et API Mapbox réels**, jeton public de configuration externe, GEBCO réel du dépôt servi localement, API administrative et PostGIS réels. Seul le dernier point de catégorie inconnue est injecté par une réponse API de test.
- Connexion, refus non-admin et mauvais mot de passe, cookies sécurisés, globe et mouvement réduit, caméra Atlantique fixe, cluster cliqué, sélection visible, liens directs, photos autorisée/masquée/absente, recherche/filtres, deux paginations, erreurs/réessai, expiration, sans token, clavier, fermeture/réouverture et cinq modérations avec CSRF/motif/confirmation/audit.
- Contrôle des exceptions JavaScript, console, réponses HTTP, transport, erreurs Mapbox et largeur des panneaux. Les réponses terrain océanique `404 {"message":"Tile not found"}` sont recensées séparément ; aucun contournement pour les autres erreurs.
- Huit captures finales des quatre vues réelles, bureau et mobile, sont conservées dans `docs/test-reports/artifacts/NW-244/`. Les artefacts et captures intermédiaires de Playwright restent ignorés.
- La recette vérifie le rendu fonctionnel des vues ; elle ne constitue pas une comparaison pixel à pixel avec des maquettes.
- **Limite acceptée explicitement par l'utilisateur** : Firebase reste simulé. Aucun compte de test confirmé ; isolation de `blueway-dev` non prouvée. Aucun compte créé, aucune requête de modération réelle. Le stockage Scaleway est simulé. La connexion Firebase et les URLs Scaleway réelles restent à valider sur des services de test isolés avant une future livraison contrôlée.

## H. Premier audit — vérification technique

Passe réalisée par le même agent que l'implémentation, distincte de la contre-revue suivante.

| Fichier et lignes finales | Scénario / anomalie | Gravité | Correction / preuve |
|---|---|---|---|
| `surveillance.js:127`, `:136`, `:154` | Lien direct avec token absent ou erreur Mapbox avant `load` : fiche inaccessible ; réponse rapide avant création de source : sélection perdue | P2 | Lecture indépendante du cycle Mapbox et mémoire `selectedData`. Tests sans token, lien du 21e élément et sélection native rendue |
| `surveillance.js:43`, `:99`, `:123`, `:160` | Ancienne lecture pouvant répondre après annulation, ou réouverture du même UUID | P2 | Comparaison du contrôleur courant et du signal, reset par sélection ; transport ignorant volontairement l'annulation dans les tests DOM |
| `admin.css:1`, `:4`, `surveillance.js:24`, `:33` | Panneau recouvrant les commandes ; deux panneaux superposés sur téléphone ; entête chevauchant le panneau de quelques pixels | P2 | Dégagement haut/bas, grille mobile et exclusivité mobile ; clic « Vue Atlantique » réel, contrôle des rectangles et screenshots |
| `surveillance.js:144`, `marker-icons.js:4` | Une catégorie future ne doit pas disparaître | P2 | Image neutre, fallback résolu, cercle si canvas indisponible ; point inconnu retrouvé dans `queryRenderedFeatures` natif |

Contrat et performances : une requête bornée 21 lignes par page ; lookahead 1 001 pour la carte. Pas de nouveau comptage global, fournisseur géographique ou requête par marqueur. Pagination OFFSET conservée, cohérente avec le domaine ; aucune promesse de snapshot immuable si les données changent entre deux pages.

Sécurité : dépendance `get_admin_context` intacte, `resolve_active_admin` réexécuté avec la vraie base de recette, cookies `__Host-`/Secure/HttpOnly/SameSite Strict, CSRF avant modération, motif/confirmation et audit transactionnel. Paramètres SQL séparés ; `textContent` pour les données ; autoescape Jinja ; aucune clé privilégiée côté navigateur. Les photos masquées ne reçoivent pas d'URL. La CSP de recette est celle du Nginx suivi ; aucun ajout de `unsafe-eval` ni changement de mécanisme d'autorisation.

Aucun défaut P0/P1 restant après corrections. Les limites Firebase/stockage sont déclarées et acceptées pour cette recette.

## I. Deuxième audit — contre-vérification du diff

Seconde passe réalisée à partir du diff réel contre `origin/dev`, incluant les nouveaux fichiers hors index avant staging. Même agent, seconde revue distincte : aucun recours à deux agents indépendants.

- Le HEAD de `origin/dev` est toujours `ec0e12e1` après un nouveau fetch. Aucun ancien commit de #131 n'est réintroduit ; la branche n'avait encore aucun commit propre avant le commit correctif.
- Contrat frontend/backend, bornes, UUID, pages vides, lookahead 20/21 et 1 000/1 001 relus. Les assertions SQL s'exécutent sur la vraie base, avec dates identiques pour éprouver l'ordre par UUID.
- Les gardes de contrôleur protègent aussi une réouverture du même utilisateur/page/UUID ; fermer le panneau invalide l'ancienne requête. Un test DOM P3 mal nommé « même UUID réouvert » ne fermait que le panneau : il a été renforcé pour réellement réouvrir le même UUID, résoudre la nouvelle réponse puis l'ancienne. Les 23 tests Node passent après cette correction de preuve.
- Les noms `marine_animal`, `obstruction`, `pollution` correspondent au domaine et à la contrainte SQL. Les trois glyphes et couleurs restent identiques ; seule l'image de secours s'ajoute. Ordre des couches et sélection native rendue au-dessus des clusters vérifiés.
- Le message de troncature limite explicitement les compteurs aux points affichés. Les tests distinguent 1 000 et 1 001, sans compter la limite atteinte comme troncature.
- Aucun changement aux contrôles serveur, cookies, CSRF, signatures photo ou règles CSP. Les cinq modérations sont testées uniquement sur les fixtures ; une photo masquée n'a pas d'URL dans la réponse.
- CI : les workflows existants gardent leurs jobs et gardes de déploiement ; seule la couverture augmente. L'authentification du serveur de test n'est jamais importée ou configurée dans le serveur produit.
- Pas de fichier Flutter, VPS, secret, base locale, cache, trace ou artefact de compilation dans le diff. Seules huit captures finales utiles sont retenues. Aucun contenu de clé n'est inclus.
- `git diff --check`, Ruff, 23 tests Node, 286 tests PostGIS et dernière recette 28/28 valides ; 32 tests API/SQL ciblés repassés après le durcissement des bornes.

Aucune régression P0/P1/P2 restante identifiée. Pas de modification fonctionnelle issue de cette seconde passe ; le renforcement du test a été revérifié. Restent les limites externes déclarées (Firebase/Scaleway réels et références graphiques absentes).

## J. GitHub et Linear

Rapport arrêté avant le commit et la publication : les liens de la nouvelle PR, son SHA final et les résultats CI réels sont fournis dans le compte rendu final et dans Linear. PR cible `dev`, reviewers `Chihaan` et `jidivici` (droits administrateur confirmés sur le dépôt). NW-244 conservera son historique et son statut ouvert ; la section corrective documentera les décisions et limites réelles.

Aucun push direct sur `dev`, aucun merge, aucun déploiement déclenché par cette mission, aucune modification du VPS, de Flutter, des données réelles ou des secrets de production.

## K. Verdict

Corrections terminées, deux passes sans défaut bloquant ; validation locale suffisante pour publier la nouvelle branche et ouvrir une PR pour revue humaine. La publication et les contrôles du commit publié sont suivis séparément. Une connexion Firebase réelle n'est pas revendiquée ; l'utilisateur demande explicitement de conserver la simulation tant que l'isolation n'est pas confirmée. Cette limite figure dans la PR et le ticket qui reste ouvert. Aucune autorisation de fusion ou de déploiement.
