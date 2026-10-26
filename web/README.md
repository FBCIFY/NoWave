# NoWave · Web

Landing maritime sombre et épurée, avec la carte de l’administration et quatre
illustrations 3D rafraîchies, ancrées sur le globe. Un geste de molette ou un
balayage passe à une seule étape. Chaque vue se stabilise avant la suivante.
Les trajets prennent le temps de reculer avant le déplacement, puis
de rejoindre progressivement la côte. Les petites corrections durent environ
une seconde ; les traversées océaniques prennent entre six et huit secondes.

## Tester localement

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
  Le parcours part de Madère et relie les Açores, Singapour et les Fidji : les grands
  déplacements reculent vers le globe avant de rejoindre la côte suivante.
- Observations fictives compactes : catégorie, texte, auteur, heure.
  La fiche donne le lieu et un historique de publication.
- Création d’un exemple depuis « Signaler » : trois catégories, commentaire
  facultatif et confirmation locale. Aucune requête de publication.
- « Mes alertes » suit la dernière slide et reste accessible par `/#alertes`,
  sans lien supplémentaire dans le header. Cette vue fixe masque le parcours ;
  son retour retrouve la dernière étape, y compris après un rechargement.
  Le rayon de 10 NM apparaît dans le sous-titre, à côté de l’activation.
  Un sonar discret en arrière-plan illustre la proximité, sans bouton de test
  ni carte de réglages. L’historique reste consultable quand les alertes sont
  désactivées ; l’animation s’arrête alors.
  Aucun appel à Notification ni demande de permission : cette démonstration
  ne modifie ni préférence réelle ni historique personnel.
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
