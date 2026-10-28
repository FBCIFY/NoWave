# Centre de surveillance web

Le navigateur utilise une session administrative Firebase existante. Les lectures sous `/admin/data` vérifient la session et répondent avec `Cache-Control: no-store`. Les actions de modération restent des formulaires serveur avec motif, confirmation, CSRF et audit.

## Cartographie

Définir `MAPBOX_PUBLIC_TOKEN` dans l'environnement du conteneur API pour activer les deux globes. Il doit s'agir d'un jeton public Mapbox limité aux domaines de l'administration. Ne pas y placer un jeton secret. Le jeton est volontairement absent de `deploy/compose.yaml` : la configuration du déploiement doit être validée séparément. Sans jeton, les formulaires et les listes fonctionnent et la carte indique son indisponibilité.

Mapbox GL JS 3.32.0 est servi localement depuis `app/web/static/` :

- `mapbox-gl.js` SHA-256 `e0f7d7ce644791a76f003da33dd4283e7a917d4a8add6a16178f5d999395b57a`
- `mapbox-gl.css` SHA-256 `6c82f3cfaa1d7bff8f6387dc3436fb5b8994f5faab20eeb417438037c361a9a7`

La CSP autorise le worker `blob:` requis, les connexions Mapbox et les photos sur les trois domaines régionaux de stockage permis. Aucun script distant ni `unsafe-eval` n'est autorisé.

Le globe et la carte plane réutilisent l'aperçu bathymétrique GEBCO déjà livré par NoWave à `/api/v1/map/seafloor/gebco-2026-v2/`. La couche raster est placée sous les traits et les libellés du style Mapbox sombre ; sa résolution native s'arrête à Z6 et elle disparaît à Z8 afin d'éviter un surzoom pixellisé. Le trait côtier léger utilise la couche `water` du source vectoriel `composite` lorsqu'elle existe. Les trois pictogrammes sont dessinés une fois sur canvas puis enregistrés comme images Mapbox, sans téléchargement par signalement. Aucun nouveau fournisseur cartographique n'a été ajouté.

Le raster doit être inséré **après** la couche vectorielle `water` de `dark-v11` ; une insertion avant celle-ci chargeait les tuiles HTTP 200 mais les rendait invisibles. Le signalement sélectionné utilise une source GeoJSON distincte afin de rester visible même lorsqu'un regroupement voisin subsiste. Un lien direct vers sa fiche rapproche la caméra au zoom 7.

Le MVP conserve au maximum **1 000 signalements par emprise**. Une ligne supplémentaire permet de distinguer exactement 1 000 résultats d'une troncature avérée à 1 001. En cas de troncature, l'interface indique « Affichage partiel » et précise que les compteurs correspondent uniquement aux signalements chargés. Les clusters sont calculés sur ces points ; leurs compteurs ne sont pas exhaustifs. Un zoom peut réduire l'emprise mais ne garantit pas l'accès à tous les signalements d'une zone très dense. Aucune agrégation serveur exhaustive n'est prévue dans ce MVP. La carte de surveillance utilise Mercator, reste orientée nord, centré initialement sur `[-30, 24]` avec un zoom `2.4`, borné de `0.5` à `12` (et ajusté aux limites mondiales de Mercator). Le globe de connexion démarre à `1.9` et tourne à `0.15°` par `1.1 s` lorsque le mouvement est autorisé. L'expansion d'un cluster utilise la fonction de rappel `getClusterExpansionZoom` de Mapbox GL JS 3.32.0.

## Recette locale nécessaire

Un compte administrateur de test, une base PostgreSQL/PostGIS contenant des données de test et un jeton public Mapbox sont nécessaires pour vérifier les interactions visuelles et les URL de photos. Aucune modération ne doit être testée sur des données de production.

En lancement FastAPI direct, le chemin GEBCO est normalement servi par Nginx (alias statique dans `deploy/web/nginx.conf`), pas par FastAPI. Une recette locale hors Docker doit donc fournir cet alias dans un serveur de développement séparé ; elle ne doit pas remplacer la route de production.

## Style cartographique

Le source `mapbox.mapbox-terrain-v2` et ses couches `landcover`/`hillshade` reprennent la méthode de `mobile/lib/core/map/globe_style.dart`. Les classes terrestres restent vectorielles : elles ne reproduisent pas une texture satellite photographique. Les libellés, frontières et routes du style de base sont masqués. Le globe reprend les couleurs atmosphériques Flutter et GEBCO conserve ses vraies couleurs sans filtre CSS. La bathymétrie s'efface progressivement entre Z6 et Z8.

Les badges circulaires cyan/orange/violet reprennent les trois couleurs Flutter. Le dauphin reprend ses points de contrôle vectoriels, l'avertissement et la goutte sont adaptés en canvas. Leur centre est ancré à la position GeoJSON. Les couleurs validées restent exactement `marine_animal: #06B6D4`, `obstruction: #F97316` et `pollution: #7C3AED`. Les clusters restent rouges (`#cf3149`). Une image neutre `#64748B` sert de secours pour une catégorie ou une image inconnue ; une indisponibilité complète du canvas utilise les cercles de secours existants. Les images sont enregistrées avant les couches qui les utilisent. Les clusters rouges et les limites de données restent inchangés. Aucun compte, signalement, trajet ni fournisseur supplémentaire n'est ajouté.


## Correctifs après fusion de la PR #131, 23 octobre 2026

Les terres utilisent une palette froide et désaturée : fond `#354b60`, bois `#344f58`, broussailles `#48616b`, herbe `#566e79`, cultures `#657b87`, neige `#c7d5df`, ombres `#263d52`, relief clair `#91a9bb`. L'eau `#002D51`, le trait côtier `#d8e4ed`, GEBCO et ses zooms ne changent pas. La géométrie et les sources restent celles déjà intégrées.

`GET /admin/data/users/{uuid}/reports?page=1` renvoie `items`, `page` et `has_more`. Les pages contiennent au maximum 20 éléments, ordonnés par observation puis UUID décroissants. Une seule requête paramétrée lit au plus 21 lignes, sans `COUNT(*)`. Une page valide au-delà de la fin retourne `items: []` et `has_more: false`. Les bornes de page du domaine restent applicables.

La fiche propose précédent/suivant, chargement, fin de liste, erreur et réessai. Sélection, nouvelle recherche et fermeture annulent les lectures précédentes ; une vérification d'identité de requête empêche aussi les réponses périmées d'écrire après une annulation tardive. Le clavier conserve un point de focus pendant la pagination. Le lien direct vers une fiche fonctionne même si la carte ne charge pas. Sur mobile, un seul panneau est ouvert à la fois ; les commandes de carte restent dégagées.

La variable `MAPBOX_PUBLIC_TOKEN` doit être injectée dans le processus API par la configuration externe approuvée lors d'une future livraison contrôlée (fichier d'environnement ou secret externe). Seul un jeton **public** limité aux domaines nécessaires est rendu dans le HTML ; aucune clé Firebase de service ne doit y figurer. Vérifier les ressources `/admin-static/`, la CSP et l'alias GEBCO avant cette livraison. Cette mission ne modifie ni la configuration du VPS ni les services de production.

Tests reproductibles, services simulés et validation Mapbox réelle : [recette navigateur](../../tests/browser/README.md). Le rapport de correction dans `docs/test-reports/NW-244-post-merge.md` distingue les résultats, les deux audits et les validations externes restantes.
