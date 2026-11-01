# Couche marine

Mapbox Standard fournit le fond et le moteur de rendu. NoWave ajoute les tuiles MVT des signalements, accessibles avec un token, les objets marins publics en GeoJSON et les rasters de fond marin. Les ouvrages portuaires gardent leur source MVT. Un problème de fournisseur marin n’empêche pas les appels de profil ou de publication.

GEBCO est un aperçu mondial précalculé, inclus dans l’image web et servi par Nginx. Le raster EMODnet ajoute le détail régional. Le backend le recolore et applique un masque d’eau OSM pour laisser la terre transparente. Une continuité locale de couleur peut combler de petits trous d’affichage ; elle ne produit ni sonde ni courbe.

Le backend choisit les fournisseurs d’après la tuile et leurs couvertures, sans utiliser la position GPS ni le pays du téléphone :

- Open Waters fournit les points de ports et le balisage OSM mondial. Les ouvrages et le masque côtier viennent de Shortbread.
- Shom apporte le balisage français, les épaves et les obstructions ; IGN apporte les ouvrages portuaires BD TOPO.
- NOAA apporte les objets ENC dans sa couverture : balisage, ouvrages, courbes, dangers et sondes.
- EMODnet fournit les courbes et le raster régional. Pour les chiffres de profondeur, son DTM prend la priorité dans sa couverture ; NOAA reste utilisé ailleurs. Une panne EMODnet ne déclenche pas de bascule vers NOAA.

Les objets gardent leur identité source, leur géométrie et les attributs publiés. Une fusion exige des éléments concordants ; deux objets seulement proches restent séparés. Les crédits et conditions de redistribution sont dans [les licences](licences.md).

Les profondeurs sont en mètres, avec leur datum quand il est connu. Les sondes NOAA conservent les valeurs ponctuelles publiées et leurs décimales. Le DTM EMODnet est une grille modélisée, parfois interpolée, référencée au LAT : ses labels sont arrondis au mètre, ou `<1`. Sa résolution native est de 1/960° ; zoomer au-delà de Z16 n’ajoute aucune mesure. Les courbes EMODnet sont généralisées au 1:500000 et ne donnent pas du détail portuaire.

## À quel zoom on charge

`MarineZoom`, dans `mobile/lib/core/map/marine/`, fixe les seuils caméra :

- GEBCO est présent dès Z0. Le détail raster EMODnet démarre à Z5.
- Les ports sont préparés à Z6, affichés à Z8 et enrichis à Z10.
- Le balisage et les dangers se chargent dès Z10, avec un fondu jusqu’à Z12. Les dangers utilisent des cellules de données au moins à Z12.
- Courbes et sondes sont préparées à Z12 et affichées à Z13. Les courbes utilisent toujours une grille de requête Z12 ; les sondes peuvent aller jusqu’à Z16.

Ces seuils ne font pas disparaître les données à un zoom supérieur. Les labels ont leurs collisions propres ; une courbe peut rester visible sans texte. Les cardinales et dangers isolés ont des couches autorisant le chevauchement. Un appui long donne accès aux objets ponctuels proches, même si leur symbole est masqué.

`MarineViewport` calcule la zone réellement couverte par la caméra, rotation, inclinaison et padding compris, avec une marge d’une cellule. Le centre visible passe avant la marge. Si la vue dépasse le budget, il réduit la résolution ou diffère le détail ; GEBCO reste dessous.

Chaque cellule GeoJSON renvoie un snapshot des objets de sa zone. Le mobile assemble ces réponses pour couvrir la vue.

## Ce qui reste pendant le déplacement

Le mobile garde un nombre limité de snapshots et de points en mémoire. Le chargement privilégie la zone visible.

Une cellule complète remplace sa propre zone. Les anciennes cellules couvrent les trous jusqu’à la relève ou leur sortie de la région utile. Les réponses partielles complètent les identités déjà présentes. Une erreur ou un partiel vide conserve le secours ; seul un vide complet confirme l’absence de données. Les courbes déjà reçues sont conservées lors d’un rafraîchissement non vide.

Le client retente les réponses partielles et les échecs, annule les demandes dépassées et suspend le chargement en arrière-plan. Recharger le style réinstalle les sources avec leur état conservé.

Les rasters réutilisent les tuiles parentes et le cache disque pendant les déplacements. Une panne du WMS ou du masque central renvoie une erreur, pas un PNG transparent accepté comme succès. Un voisin de masque facultatif manquant peut laisser un rendu partiel ; celui-ci n’est pas mis en cache côté serveur.

## Côté serveur

Le résultat GeoJSON/MVT est mis en cache en RAM, séparément des réponses fournisseurs. Les demandes identiques partagent le chargement. Ce cache serveur est distinct du contrat HTTP : les sondes portent `no-store`.

Les réponses fournisseurs réutilisables passent dans un SQLite local. Les clients de sondes EMODnet et NOAA ne stockent pas leurs corps numériques sur disque. Les obligations de cache OSM restent celles des licences ; une panne ou une saturation de ce cache ne doit pas être contournée par des téléchargements répétés.

Les PNG régionaux terminés ont leur propre cache en RAM et sur disque. `MARINE_CACHE_DIR` choisit le répertoire des SQLite ; en production, le volume `marine-cache` est monté sur `/var/cache/nowave/marine`. Conserver SQLite, WAL et SHM ensemble.

Le transport partagé limite les appels simultanés et borne les délais ; chaque fournisseur dispose aussi d’une échéance. Les erreurs déclenchent une temporisation plutôt qu’une boucle de requêtes. Les budgets sont par processus : ajouter des workers multiplie la charge amont.

Pour une erreur de carte, distinguer le statut HTTP, `X-NoWave-Marine-Status`, un résultat vide complet et un résultat dégradé. Le détail des formats et des réponses reste dans les contrats API. `MARINE_DISABLED_PROVIDERS` permet de désactiver des fournisseurs au démarrage pour tester une panne ; il faut redémarrer le service après un changement.

`MARINE_API_BASE_URL` peut viser un backend marin séparé. Les appels restent publics, sans token Firebase ; les signalements et les autres opérations métier restent sur `API_BASE_URL`. Mapbox et les téléchargements GeoJSON Dart ont des budgets séparés.

Ces données servent à l’affichage. Elles ne remplacent pas les cartes officielles et ne permettent pas de calculer une marge sous quille.
