# NoWave web

Site de présentation avec un parcours animé, une démo des signalements et des
alertes, puis une carte publique. La carte et l’administration partagent le même
composant et les mêmes assets.

## Lancer avec le backend local

Depuis la racine du dépôt, compléter `.env` à partir de `.env.example`, puis :

```sh
docker compose up --build -d --wait
```

Ouvrir [le site local](https://localhost:8443) ou
[l’administration locale](https://localhost:8443/admin) et accepter le certificat
local. Les migrations s’appliquent automatiquement et la base existante est
conservée. La connexion admin demande un compte Firebase vérifié et un profil
`admin` dans cette base. Renseigner `MAPBOX_PUBLIC_TOKEN` avec un jeton autorisé
pour localhost.

## Lancer un aperçu sans base réelle

Sur macOS, ouvrir `Tester la refonte.command` dans ce dossier. Le lanceur choisit
des ports libres, démarre l’aperçu et ouvre le navigateur.
Le compte de démo est `admin@nowave.test` / `preview-only`.

Pour lancer les services manuellement, avec Node.js 22.12+ et les dépendances
Python de test installées, depuis la racine :

```sh
PYTHONPATH=backend python backend/tests/browser/preview.py --port 8000
```

Dans un second terminal :

```sh
cd web
npm ci
npm run dev -- --port 5173
```

Ouvrir [l’aperçu local](http://127.0.0.1:5173/). Les données sont synthétiques,
en mémoire, et la modération est désactivée. La démo ne publie aucun signalement
et ne demande ni géolocalisation ni autorisation de notifications.

Le fond de carte demande `MAPBOX_PUBLIC_TOKEN`, ou `NOWAVE_MAPBOX_CONFIG` pointant
vers un JSON contenant `MAPBOX_ACCESS_TOKEN`. Sans jeton, le reste du site reste
consultable. `NOWAVE_API_URL` change la destination du proxy Vite, qui transmet
`/api`, `/admin` et `/admin-static` au backend local sur le port 8000 par défaut.

## Comportement

Le parcours présente le phare, l’animal marin, l’obstacle, la pollution et les
alertes. Molette, gestes, boutons et flèches clavier changent d’étape. Les
animations respectent `prefers-reduced-motion` et s’arrêtent quand l’onglet est
masqué. Les exemples du parcours restent fictifs.

`/#carte` ouvre la carte libre ; `/#alertes` ouvre l’étape des alertes.
La carte publique charge les observations actives via
`/api/v1/map/observations`, par pages de 50. Une erreur API affiche un état
indisponible. Le pseudo apparaît seulement avec le consentement de l’auteur.

`map-view.js` est partagé entre carte publique et admin. `admin-map.js` ajoute
les liens et actions d’administration. Les pages et lectures privées restent
authentifiées ; les actions demandent une confirmation et un token CSRF.
`/api/v1/map/web-config` fournit uniquement le jeton public de cartographie.
Les crédits restent visibles au bas de la carte.

Le build produit les entrées publique et admin, avec le CSS commun
`/assets/nowave.css`. En production, servir les assets du même build que les
pages admin. Voir [le déploiement](../deploy/README.md).

## Assets et vérifications

Les illustrations utilisées sont `lighthouse-v3.png`, `whale-v3.png`,
`container-v3.png` et `pollution-v3.png`. Le phare est fictif.
Les fichiers de marque sont décrits dans [le guide des assets](public/brand/README.md).

Depuis la racine :

```sh
npm ci --prefix web
npm test --prefix web
npm run build --prefix web
npm run format:check --prefix web
node --test backend/tests/web/*.cjs
PYTHONPATH=backend python -m pytest backend/tests/api/test_map_web_config.py backend/tests/api/test_admin_web_pages.py backend/tests/api/test_admin_web.py
```

Vérifier sur ordinateur et mobile les transitions, fiches, formulaire, alertes,
carte et erreurs de chargement. La recette avec PostgreSQL isolé est décrite
dans [les tests navigateur](../backend/tests/browser/README.md).
