# NoWave · Web

Landing page et carte pédagogique interactive, indépendantes du mobile et de l’API.
L’expérience explique la mission de l’application : partager une observation
géolocalisée dans les catégories **Obstacle**, **Animal marin** et **Pollution**.

## Démarrage local

Node.js 22.12+ (ou 24 LTS) et npm :

Sur macOS, double-cliquer sur **Lancer NoWave.command** dans ce dossier. Le script
installe les dépendances si nécessaire, compile le site et ouvre
http://127.0.0.1:4173. Garder le terminal ouvert ; `Ctrl+C` arrête le serveur.
Si NoWave occupe déjà ce port, le script réutilise ce serveur. Un autre service
sur ce port est conservé et une erreur explicite demande de choisir
`NOWAVE_LOCAL_PORT`.

Depuis un terminal :

```sh
cd web
npm ci
npm start
```

Pour développer avec rechargement automatique :

```sh
cd web
npm ci
npm run dev
```

Ouvrir http://127.0.0.1:5173. Le serveur écoute uniquement sur la boucle locale.

## Service Docker

Depuis la racine, pour lancer le site seul sans la base ni ses variables :

```sh
docker compose -f web/compose.yaml up --build -d
```

Ouvrir http://127.0.0.1:8080. `NOWAVE_WEB_PORT` permet de choisir un autre port.
La composition principale du dépôt inclut également le service `web` :

```sh
# Avec les variables habituelles du projet déjà configurées
docker compose up --build -d web
```

Le Dockerfile compile les fichiers avec Node puis les sert via Nginx.
`GET /health` retourne `{"status":"ok","service":"nowave-web"}`.
Aucune dépendance envers l’API ni PostgreSQL pour cette landing page.

## Expérience

- Visite de 11 repères au défilement dans un même archipel : phare, épave, plastique,
  Nautilus, message, conteneur, baleine, orque, observation, observatoire et glaces.
  Le texte apparaît à côté du sujet sur ordinateur, sous le sujet sur mobile.
  Le récapitulatif termine le parcours avec les trois catégories et les quatre
  informations d’un signalement.
- Navigation directe entre les étapes et retour en arrière au défilement.
  Un geste de molette, de trackpad ou de toucher avance d’un seul repère. Chaque
  transition dure 1,5 seconde et va jusqu’au cadrage final ; l’inertie du geste
  ne déclenche pas une deuxième étape. Un nouveau geste pendant le déplacement
  mémorise une étape suivante, exécutée après l’arrivée et une courte pause.
  La caméra se déplace directement entre ses deux cadrages avec un départ et
  une arrivée progressifs. Un relâchement de la barre de défilement
  entre deux repères recale la visite sur le plus proche. Le défilement redevient
  libre après le parcours. Aucune étiquette permanente ni fiche automatique.
- Zoom sur un objet net avec la carte et les autres éléments toujours visibles,
  légèrement floutés en arrière-plan pour dégager la lecture.
- Le premier repère montre le vrai phare et son village dans l’archipel. Un masque
  SVG adoucit le contour de la zone nette sans substituer une autre île.
- L’iceberg est placé en pleine eau. Sa partie immergée se révèle progressivement
  à l’approche pendant le parcours ou lorsque l’on zoome en exploration libre.
- Mode exploration activé uniquement au clic : 11 repères, déplacement à la souris ou au toucher, pincement et molette
  pour zoomer, boutons de zoom et recentrage.
- Clavier dans la carte : flèches, `+`, `−`, `0` ; `Échap` pour quitter l’exploration.
- Fiches sur les conteneurs perdus, les collisions avec les cétacés, les interactions
  avec certaines orques, les icebergs, les déchets et la qualité des observations.
- Exemple de signalement : catégorie, coordonnées fictives, commentaire limité à
  250 caractères, aperçu. **Aucune requête à l’API, aucun signalement réel créé.**
- Pas de stockage local ni d’ambiance sonore. La caméra s’arrête au repos,
  lorsqu’un dialogue est ouvert et quand l’onglet est masqué.
- Pause des animations et prise en compte de `prefers-reduced-motion` : changements
  de plans sans déplacement interpolé pour la visite guidée.
- Polices hébergées dans le build ; aucun CDN, tracker ni cookie tiers.

## Assets et contenu

Les visuels originaux générés par l’outil intégré OpenAI `image_gen` sont dans
`public/assets/`, au format WebP qualité 94, avec alpha et définition native
conservés pour les assets actifs. Le fond remasterisé est livré en 1536 × 1024 ;
les objets isolés disposent de 1254 à 1536 pixels de large. Le phare du parcours
reprend directement l’îlot central de ce fond. Le premier asset de phare séparé
reste archivé, sans être utilisé à l’écran. Les prompts sont dans
`assets-manifest.json` et `prompts/archipelago-remaster.txt`.

La composition riche en détails s’inspire du principe d’exploration de
[Floor796](https://floor796.com/) ; aucun asset du site de référence n’est repris.
Les scènes sont illustratives, les positions fictives, et les échelles non réalistes.
Ce site n’est ni une carte de navigation ni un service d’alerte maritime.
L’application mobile est présentée comme un projet en développement, sans faux
bouton de téléchargement ni promesse de détection automatique.

Les sources primaires sont regroupées dans `src/data.js` et liées dans les fiches :

- [OMI — conteneurs et objets perdus](https://www.imo.org/en/mediacentre/hottopics/pages/container-default.aspx)
- [OMI — déchets marins](https://www.imo.org/en/mediacentre/hottopics/pages/marinelitter-default.aspx)
- [NOAA — collisions avec la faune marine](https://www.fisheries.noaa.gov/national/endangered-species-conservation/vessel-strikes)
- [US Coast Guard — International Ice Patrol](https://www.navcen.uscg.gov/international-ice-patrol-about-us)
- [MITECO — interactions avec les orques, 2026](https://www.miteco.gob.es/es/prensa/ultimas-noticias/2026/marzo/-disminuyen-en-espana-las-interacciones-con-orcas--excepto-en-el.html)

Les catégories correspondent à `ReportCategory` dans le mobile et l’API. La durée
de validité de 24 heures décrite dans l’observatoire correspond au modèle actuel
`backend/app/domain/report.py`. Les fiches pédagogiques ne remplacent pas les
consignes officielles locales actualisées.

## Vérification

```sh
npm test
npm run build
npm run format:check
docker compose config
```

Le build vérifie d’abord la présence des assets utilisés. Les tests couvrent les
11 étapes, leur contenu et leurs catégories, la continuité du parcours dans les
deux sens, les limites, l’amortissement indépendant de la fréquence d’affichage
et le mode à mouvements réduits. Vérifier aussi dans le navigateur la vue
d’ensemble, les 11 cadrages, le récapitulatif, les dialogues, la révélation de
l’iceberg, l’exploration, le clavier et l’affichage mobile.
Les tests de gestes couvrent l’inertie longue, les petits mouvements cumulés,
les inversions et un nouveau geste interrompant l’inertie du précédent.
Le contrôle Docker de configuration ne nécessite pas de daemon. Pour vérifier
le service réel, Docker doit être démarré :

```sh
docker compose up --build -d --wait
curl --fail http://127.0.0.1:8080/health
```
