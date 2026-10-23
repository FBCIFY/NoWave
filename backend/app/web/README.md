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

Les points sont lus par emprise avec une limite de 1 000 ; si la limite est atteinte, l'interface demande de zoomer. Le nombre de chaque cluster correspond exactement aux points chargés dans cette emprise. La carte de surveillance utilise Mercator, reste orientée nord, centré initialement sur `[-30, 24]` avec un zoom `2.4`, borné de `0.5` à `12` (et ajusté aux limites mondiales de Mercator). Le globe de connexion démarre à `1.9` et tourne à `0.15°` par `1.1 s` lorsque le mouvement est autorisé. L'expansion d'un cluster utilise la fonction de rappel `getClusterExpansionZoom` de Mapbox GL JS 3.32.0.

## Recette locale nécessaire

Un compte administrateur de test, une base PostgreSQL/PostGIS contenant des données de test et un jeton public Mapbox sont nécessaires pour vérifier les interactions visuelles et les URL de photos. Aucune modération ne doit être testée sur des données de production.

En lancement FastAPI direct, le chemin GEBCO est normalement servi par Nginx (alias statique dans `deploy/web/nginx.conf`), pas par FastAPI. Une recette locale hors Docker doit donc fournir cet alias dans un serveur de développement séparé ; elle ne doit pas remplacer la route de production.

## Refonte selon les références locales

`photo/image.png` guide le globe de connexion et `photo/image2.png` la carte plane. Le source `mapbox.mapbox-terrain-v2` et ses couches `landcover`/`hillshade` reprennent la méthode de `mobile/lib/core/map/globe_style.dart`. Les classes terrestres restent vectorielles : elles ne reproduisent pas une texture satellite photographique. Les libellés, frontières et routes du style de base sont masqués. Le globe reprend les couleurs atmosphériques Flutter et GEBCO conserve ses vraies couleurs sans filtre CSS. La bathymétrie s'efface progressivement entre Z6 et Z8.

Les badges circulaires cyan/orange/violet reprennent les trois couleurs Flutter. Le dauphin reprend ses points de contrôle vectoriels, l'avertissement et la goutte sont adaptés en canvas. Leur centre est ancré à la position GeoJSON. Les clusters rouges et les limites de données restent inchangés. Aucun compte, signalement, trajet ni fournisseur supplémentaire n'est ajouté.
