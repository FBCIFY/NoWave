# Centre de surveillance web

L'accueil `/admin` utilise une session administrative Firebase. Il charge l'entrée `web/admin-map.js` et le composant `web/src/map-view.js`, partagé avec la carte publique. Les lectures privées sous `/admin/data` vérifient la session et répondent avec `Cache-Control: no-store`. Les actions de modération restent des formulaires serveur avec motif, confirmation, CSRF et audit.

## Cartographie

Définir `MAPBOX_PUBLIC_TOKEN` dans l'environnement du conteneur API pour activer les globes de connexion et de surveillance. Il doit s'agir d'un jeton public Mapbox limité aux domaines du site et de l'administration. Ne pas y placer un jeton secret. Le jeton est volontairement absent de `deploy/compose.yaml` : la configuration du déploiement doit être validée séparément. Sans jeton, les formulaires et les listes fonctionnent et la carte indique son indisponibilité.

Mapbox GL JS 3.32.0 est servi localement depuis `app/web/static/` :

- `mapbox-gl.js` SHA-256 `e0f7d7ce644791a76f003da33dd4283e7a917d4a8add6a16178f5d999395b57a`
- `mapbox-gl.css` SHA-256 `6c82f3cfaa1d7bff8f6387dc3436fb5b8994f5faab20eeb417438037c361a9a7`

La CSP autorise le worker `blob:` requis, les connexions Mapbox et les photos sur les trois domaines régionaux de stockage permis. Aucun script distant ni `unsafe-eval` n'est autorisé.

Les deux globes réutilisent l'aperçu bathymétrique GEBCO déjà livré par NoWave à `/api/v1/map/seafloor/gebco-2026-v2/`. Sa résolution native s'arrête à Z6 et la couche raster disparaît à Z8 afin d'éviter un surzoom pixellisé. Le trait côtier léger utilise la couche `water` du source vectoriel `composite` lorsqu'elle existe. Aucun nouveau fournisseur cartographique n'a été ajouté.

Le raster doit être inséré **après** la couche vectorielle `water` de `dark-v11` ; une insertion avant celle-ci chargeait les tuiles HTTP 200 mais les rendait invisibles.

La carte de surveillance utilise la projection globe, reste orientée nord et démarre sur `[-20, 25]`. Son zoom initial s'adapte à l'espace disponible entre `0.5` et `1.75` ; la navigation permet d'atteindre Z12. La sélection d'une observation rapproche la caméra à Z7.2. Le globe de connexion démarre à `1.9` et tourne à `0.15°` par `1.1 s` lorsque le mouvement est autorisé.

Le fil affiche les observations actives, des plus récentes aux plus anciennes, par pages de **50** via `/api/v1/map/observations`. Il est indépendant de l'emprise visible et propose des filtres par catégorie ainsi qu'une recherche par description ou pseudo. Chaque observation de la page possède un marqueur individuel ; le compteur indique le nombre chargé sur cette page. La pagination utilise les curseurs renvoyés par l'API et permet de parcourir le fil au-delà de 1 000 observations.

La sélection charge les détails privés via `/admin/data/reports/{uuid}` et propose les liens vers la fiche, l'historique et les actions autorisées selon l'état du signalement et de sa photo. Les rubriques Utilisateurs, Modération et Audit restent des pages administratives distinctes.

La route historique `/admin/data/reports?west=...&south=...&east=...&north=...` reste disponible avec session administrative. Elle renvoie au maximum **1 000 signalements par emprise**, avec une ligne supplémentaire pour déterminer le champ `truncated`. Ce contrat est conservé dans le backend ; l'accueil partagé utilise le fil paginé décrit ci-dessus.

## Recette locale nécessaire

Un compte administrateur de test, une base PostgreSQL/PostGIS contenant des données de test et un jeton public Mapbox sont nécessaires pour vérifier l'intégration réelle et les URL de photos. Le [lancement local du site](../../../web/README.md#tester-localement) décrit la pile Docker HTTPS et l'aperçu synthétique avec Vite. Aucune modération ne doit être testée sur des données de production.

Le serveur FastAPI seul ne sert pas le build web `/assets/admin-map.js` et `/assets/nowave.css`, ni l'alias GEBCO normalement fourni par Nginx. La pile Docker locale sert ces ressources sur la même origine. Pour l'aperçu synthétique, lancer `backend/tests/browser/preview.py` avec Vite puis ouvrir l'administration sur le port Vite : le proxy transmet le contexte de développement pour charger l'entrée source, et le serveur d'aperçu monte temporairement les tuiles GEBCO. La [recette navigateur](../../tests/browser/README.md) détaille les commandes et les services simulés.

## Style cartographique

Le source `mapbox.mapbox-terrain-v2` et ses couches `landcover`/`hillshade` reprennent la méthode de `mobile/lib/core/map/globe_style.dart`. Les classes terrestres restent vectorielles : elles ne reproduisent pas une texture satellite photographique. Les libellés, frontières et routes du style de base sont masqués. Le globe reprend les couleurs atmosphériques Flutter et GEBCO conserve ses vraies couleurs sans filtre CSS. La bathymétrie s'efface progressivement entre Z6 et Z8.

Les badges circulaires cyan/orange/violet reprennent les trois couleurs Flutter. Le dauphin reprend ses points de contrôle vectoriels, l'avertissement et la goutte sont adaptés en canvas. Le composant partagé convertit ces pictogrammes en images pour ses marqueurs HTML Mapbox, centrés sur les coordonnées des observations. Les couleurs validées restent exactement `marine_animal: #06B6D4`, `obstruction: #F97316` et `pollution: #7C3AED`.

Les terres utilisent une palette froide et désaturée : fond `#354b60`, bois `#344f58`, broussailles `#48616b`, herbe `#566e79`, cultures `#657b87`, neige `#c7d5df`, ombres `#263d52`, relief clair `#91a9bb`. L'eau `#002D51`, le trait côtier `#d8e4ed`, GEBCO et ses zooms ne changent pas. La géométrie et les sources restent celles déjà intégrées.

## Lectures administratives et navigation

`GET /admin/data/users/{uuid}/reports?page=1` renvoie `items`, `page` et `has_more`. Les pages contiennent au maximum 20 éléments, ordonnés par observation puis UUID décroissants. Une seule requête paramétrée lit au plus 21 lignes, sans `COUNT(*)`. Une page valide au-delà de la fin retourne `items: []` et `has_more: false`. Les bornes de page du domaine restent applicables.

La page `/admin/users/{uuid}/reports` utilise cette même pagination par 20 avec les liens précédent/suivant. L'accueil ne charge pas de panneau utilisateurs dans la carte.

Le fil d'observations propose chargement, pagination, erreur et réessai. Les nouvelles lectures annulent la précédente et vérifient l'identité de la requête avant d'afficher la réponse. Les détails privés vérifient également la sélection courante. Les retours entre liste, fiche et action conservent le cadrage, les filtres et la pagination dans l'onglet. Le lien direct vers une fiche fonctionne même si la carte ne charge pas. Sur mobile, la liste et la fiche s'affichent alternativement.

La variable `MAPBOX_PUBLIC_TOKEN` doit être injectée dans le processus API par la configuration externe du déploiement. Le formulaire de connexion reçoit ce jeton public dans le HTML ; la carte partagée le récupère via `/api/v1/map/web-config`. Aucune clé Firebase de service ne doit être exposée. Avant une livraison, vérifier les ressources `/admin-static/`, le build web partagé sous `/assets/`, la CSP et l'alias GEBCO.

Tests reproductibles, services simulés et validation Mapbox réelle : [recette navigateur](../../tests/browser/README.md). Le [rapport de bug tracking Stage 4](../../../docs/NoWave_Rapport_Bug_Tracking.pdf) reprend les corrections et leurs limites ; les comptes rendus NW-244 détaillés restent dans l'historique Git.
