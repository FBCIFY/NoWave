# NoWave · Web

Landing maritime sombre et épurée, avec la carte de l’administration et quatre
illustrations 3D rafraîchies, ancrées sur le globe. Un geste de molette ou un
balayage passe à une seule étape. Continuer à défiler accélère progressivement
le trajet en cours, puis la caméra freine et se stabilise au repère.
Un saut de plusieurs slides utilise un trajet plus court vers la destination choisie. L’inertie
ne déclenche pas l’étape suivante.
Les étapes parcourent plusieurs îles de l’Atlantique : Madère, Tenerife,
Grande Canarie, Santo Antão et Sal. Les observations restent en mer,
près des côtes. Les transitions régionales prennent environ deux secondes,
avec un recul modéré de la caméra plutôt qu’un tour du globe.
L’accélération du trackpad reste limitée et ignore les petites fins de geste.
Un geste opposé inverse le déplacement en cours vers le repère voisin.

## Tester localement

### Avec la base locale et les secrets de développement

Depuis la racine du dépôt, renseigner `.env` à partir de `.env.example`, puis :

```sh
docker compose up --build -d --wait
```

Site : **https://localhost:8443**. Admin : **https://localhost:8443/admin**.
Accepter le certificat local lors de la première ouverture. Le backend et le
web utilisent le code de la branche, les mêmes Dockerfiles que le déploiement
et une seule origine HTTPS. Les cookies admin restent sécurisés.
Les migrations sont automatiques ; la base existante est conservée. Aucun compte
ni signalement de démonstration n’est ajouté. La connexion demande un compte
Firebase vérifié avec un profil `admin` dans cette base locale.
`MAPBOX_PUBLIC_TOKEN` doit être renseigné et autorisé pour localhost.
Les ports peuvent être changés dans `.env`.

### Aperçu synthétique sans secrets

Sur macOS, ouvrir **Tester la refonte.command**. Le lanceur démarre la landing
et le backend de démonstration, choisit des ports libres et ouvre le navigateur.

- Landing : http://127.0.0.1:5173/
- Carte consultable : http://127.0.0.1:5173/#carte
- Alertes de proximité : http://127.0.0.1:5173/#alertes
- Administration : http://127.0.0.1:5173/admin
- Connexion de démonstration : **admin@nowave.test** / **preview-only**

Le serveur utilise des données synthétiques en mémoire, sans base réelle ni
Firebase. La modération est désactivée dans cet aperçu. Aucun accès admin
n’apparaît sur la landing. Sur HTTP local, des cookies d’aperçu distincts
permettent la connexion dans Safari ; les contrôles de session et de CSRF
restent actifs et les cookies de production restent sécurisés.

Pour démarrer manuellement depuis la racine :

```sh
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
# Dans un second terminal :
cd web
npm ci
npm run dev -- --port 5173
```

Node 22.12+ et les dépendances Python de test sont nécessaires.
La carte utilise un jeton public Mapbox autorisé pour localhost :
`MAPBOX_PUBLIC_TOKEN` ou `NOWAVE_MAPBOX_CONFIG` (JSON avec `MAPBOX_ACCESS_TOKEN`).
Le lanceur peut retrouver la configuration du checkout principal.
Les fonds GEBCO proviennent du bundle existant. Sans jeton, les illustrations
et démonstrations restent consultables avec un bouton de réessai de la carte.

Le proxy Vite transmet `/api`, `/admin` et `/admin-static` au backend local 8000.
`NOWAVE_API_URL` permet de modifier cette destination.
Les variables du lanceur `NOWAVE_PREVIEW_API_PORT`, `NOWAVE_PREVIEW_WEB_PORT`,
`NOWAVE_PREVIEW_PYTHON` et `NOWAVE_PREVIEW_NO_OPEN` sont facultatives.

## Parcours

- Accueil avec phare 3D, puis animal marin, obstacle et pollution.
  Le phare reste à Madère. La baleine se trouve au large de Tenerife, le conteneur
  au large d’Agaete, à l’ouest de Grande Canarie, et les déchets près de Santo Antão, au Cap-Vert.
  Le sonar termine le parcours au large de Sal, plus à l’est dans le même archipel.
  Les observations et l’emprise de leurs illustrations gardent une marge en mer
  par rapport aux côtes, y compris pendant les transitions.
- Observations fictives compactes : catégorie, texte, auteur, heure.
  La fiche donne le lieu et un historique de publication.
- Création d’un exemple depuis « Signaler » : trois catégories, commentaire
  facultatif et confirmation locale. Aucune requête de publication.
- « Mes alertes » est la quatrième slide, juste après les déchets, sur la même
  carte du parcours. La caméra rejoint progressivement le sonar avec le même
  freinage que les autres étapes. Aucun lien supplémentaire dans le header.
  Le lien `/#alertes` et le dernier point du parcours ciblent cette slide.
  Le parcours s’y arrête : continuer le geste ne peut pas ouvrir la carte libre.
  Le panneau garde « Mes alertes », le rayon de 10 NM, une courte accroche et
  trois exemples. Les fiches montrent uniquement le type, la description,
  l’heure, la distance et le lieu. Sur mobile, elles restent dans la partie basse
  et laissent le sonar visible. Les barres de défilement et l’indicateur de slides
  sont masqués ; les gestes et le clavier restent disponibles.
  La sélection et le retour d’une alerte gardent exactement le même cadrage.
  Le panneau explique les notifications de l’application, sans interrupteur fictif.
  Le sonar reprend le mobile : trois fronts géographiques rouges avec halo,
  espacés de deux secondes, qui atteignent le point GPS en six secondes en
  s’effaçant. Les exemples sont situés au large de Sal, à la distance affichée
  du même point GPS fictif. Aucun second moteur de carte n’est créé.
  Les couches et l’animation s’arrêtent dès que la slide est quittée.
  Le mode à mouvements réduits conserve les marqueurs.
  Aucun appel à Notification ni demande de géolocalisation ou de permission :
  cette démonstration ne modifie ni préférence réelle ni historique personnel.
- Onglet « La carte » en pleine page, accessible directement via `/#carte`.
  Le panneau gauche affiche les observations actives les plus récentes,
  provenant de `/api/v1/map/observations`, indépendamment de la zone visible.
  La carte est décalée dans l’espace à droite du panneau. Les pages de 50
  observations permettent de consulter l’ensemble du fil sans plafond de 1000.
  Les filtres reprennent les trois items du formulaire du parcours ; la recherche
  de lieux a été retirée. Les observations
  expirées ou retirées sont exclues. Les champs absents restent masqués et
  le pseudo apparaît uniquement avec le consentement de son auteur.
  L’aperçu local fournit trois fixtures via ce même contrat ; aucun faux
  signalement ne remplace une erreur API. Échap ferme la fiche ou la liste.
  Le retour du navigateur retrouve la position du parcours.
- Navigation par gestes, boutons ou flèches du clavier. Les animations
  gardent une seule slide visible, suivent `prefers-reduced-motion` et se
  reposent lorsque l’onglet est masqué.

La carte publique et l’administration montent le même composant `map-view.js`,
avec le même header transparent, le même panneau et les mêmes filtres.
L’entrée `admin-map.js` ajoute uniquement les liens Utilisateurs, Modération,
Audit et les actions protégées des fiches. Aucun panneau utilisateurs ni
recherche de lieux n’est chargé dans la carte. Les crédits et le logo requis
sont réunis au bas de la carte, toujours visibles ; les indications de
démonstration sont regroupées au pied de page.

Les lectures publiques ne demandent aucune donnée administrative.
`/api/v1/map/web-config` expose uniquement un jeton public valide, sans cache.
Le moteur, le style maritime et les marqueurs réutilisent les fichiers
`/admin-static/`. Le conteneur web autonome indique clairement l’absence de
cartographie quand le backend n’est pas disponible.

Le build produit les entrées publique et admin ainsi qu’un seul CSS partagé
`/assets/nowave.css`. Le backend admin authentifie toujours la page et les
lectures privées ; les actions gardent leurs pages de confirmation et leur CSRF.
Les retours remontent une étape à la fois (liste ou carte, fiche, action), avec
le cadrage, les filtres et la pagination conservés dans l’onglet. Les destinations
de retour sont limitées aux pages de la même administration.
En développement, Vite transmet son contexte et sert l’entrée source. En
production, le frontal doit servir les assets du même build que la page admin.

## Illustrations

Versions utilisées : `lighthouse-v3.png`, `whale-v3.png`,
`container-v3.png`, `pollution-v3.png`.
Les visuels adoptent les teintes de la carte, avec une vue plongeante pour
la baleine et des contours d’eau transparents. Ils sont placés au large,
près des côtes de chaque escale. Le phare est une illustration fictive.

## Vérification

```sh
npm test --prefix web
npm run build --prefix web
npm run format:check --prefix web
node --test backend/tests/web/*.cjs
PYTHONPATH=backend python -m pytest backend/tests/api/test_map_web_config.py backend/tests/api/test_admin_web_pages.py backend/tests/api/test_admin_web.py
```

Contrôler sur ordinateur et mobile le calage des trois étapes après l’accueil,
les fiches, le formulaire, les alertes, la carte et son état indisponible.
L’administration affiche les observations et leur auteur avec un historique
réel filtré par signalement, y compris les actions sur la photo associée.
La recette PostgreSQL isolée est décrite dans `backend/tests/browser/README.md`.
