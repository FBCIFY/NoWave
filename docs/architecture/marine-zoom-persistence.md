# Chargement et conservation des couches marines

`MarineViewport` charge les données utiles à la caméra Mapbox et conserve les
cellules encore nécessaires pendant leur remplacement. Les limites de la vue
incluent rotation, inclinaison, padding et une marge d'une cellule.

## Seuils de zoom

Les seuils utilisent le zoom fractionnaire de la caméra et sont centralisés dans
[MarineZoom](../../mobile/lib/core/map/marine/marine_zoom.dart).

| Zoom | Comportement |
| --- | --- |
| Z5 | Affichage du raster marin |
| Z6 | Préchargement des ports |
| Z8 | Affichage des ports |
| Z10 | Enrichissement portuaire et préchargement des marques/dangers |
| Z10–12 | Fondu linéaire des marques : 0 % à Z10, 50 % à Z11, 100 % à Z12 |
| Z12 | Préchargement des courbes et sondes |
| Z13 | Affichage des courbes, de leurs labels et des sondes |

À Z10 exactement, les sources de placement des marques restent vides pour ne
pas réserver de collisions invisibles. Les couches n'ont pas de seuil supérieur
de disparition ; zoomer davantage ne produit pas de données plus précises.

## Snapshots et budgets

Le mobile appelle `/api/v1/map/marine-features/{family}/{z}/{x}/{y}.geojson`
sans token Firebase. Le backend réutilise fournisseurs, normalisation et cache
existants. Les infrastructures portuaires gardent leur route MVT séparée.

| Famille | Zooms de requête acceptés |
| --- | --- |
| `harbours` | Z6–14 |
| `seamarks` | Z10–14 |
| `underwater-hazards` | Z10–14, données à partir de Z12 |
| `depth-contours` | Z12 uniquement |
| `soundings` | Z10–16, données à partir de Z12 |

Les marques et dangers sont demandés à la résolution Z12 dès le préchargement.
Les courbes restent sur une grille Z12 fixe ; les sondes peuvent aller jusqu'à
Z16. Les autres familles sont plafonnées à Z14.

| Budget mobile | Limite |
| --- | --- |
| Cellules de travail et cache | 64 snapshots, 12 Mio de JSON encodé |
| Téléchargements GeoJSON | 2 simultanés |
| Points retenus en complément | 8 000 points, 4 Mio encodés |
| Réponse serveur | 6 000 objets et 4 Mio maximum |

La couverture visible passe avant la marge, par anneaux autour du centre.
Le calcul vise 48 cellules visibles pour garder de la place aux transitions et
au détail central. Si nécessaire, il réduit la résolution jusqu'à Z6 pour les
ports et Z12 pour les autres familles. Si cela ne suffit pas, il charge d'abord
le centre ; le fond mondial GEBCO garde la couverture périphérique.
Une tuile portuaire Z6 peut agréger plusieurs tuiles fournisseur Z8.

Ces budgets comptent les données encodées ; ils n'incluent pas les objets Dart,
les buffers GPU ni toute la mémoire native Mapbox.

## Remplacement et erreurs

Une réponse complète remplace sa propre zone. Les cellules précédentes couvrent
les trous restants, puis sont libérées lorsque la relève est complète ou qu'elles
sortent de la région utile. Un résultat complet vide confirme l'absence de données ;
une erreur ou un résultat partiel vide conserve le secours existant.

Les lignes et surfaces sont découpées selon les couvertures restantes, sans
transformer leurs nouvelles limites en objets physiques. Les fragments d'une
même identité sont réunis. L'admission en cache et le retrait des anciennes
cellules sont atomiques ; une saturation diffère le détail ou réduit la résolution.

Le client annule les demandes dépassées et suspend le chargement en arrière-plan.
Les erreurs et réponses partielles sont retentées après environ 15–16 s. Une
erreur n'est jamais enregistrée comme une cellule vide. Les diagnostics ne gardent
que les cellules demandées par la vue actuelle.

## Ports, marques et profondeurs

Les ports viennent d'Open Waters. Leur sélection utilise les positions écran
Mapbox ; les représentants déjà visibles gardent leur priorité sur les nouveaux.
Une collision forcée par une rotation peut masquer un symbole, mais l'objet reste
consultable par appui long. Revenir sous Z8 réinitialise cette sélection.

Les marques et dangers ponctuels suivent le fondu Z10–12. Les cardinales et
dangers isolés disposent de couches de sécurité autorisant le chevauchement.
Les autres collisions restent actives. L'appui long liste les ports, marques et
dangers ponctuels proches, y compris ceux dont le symbole est masqué.

Les courbes gardent leurs géométries et identités pendant le zoom. Leur visibilité
ne dépend pas du placement d'un label ; les étiquettes ont leurs collisions propres.
Un rafraîchissement partiel ajoute les nouvelles identités aux précédentes.
Les sources sont reconstruites après rechargement du style en conservant cet état.
Les [règles hydrographiques](hydrography.md) précisent sélection et datums.

## Raster et déplacements rapides

Le fond GEBCO mondial reste sous le détail régional EMODnet. Les deux sources
utilisent `prefetchZoomDelta: 4`. Le détail régional garde ses tuiles parentes,
son cache disque et son fondu. Il utilise des tuiles 256 px, jusqu'à Z14.

L'emprise EMODnet va de 73,125° O à 45° E et de 5,625° N à 85,051129° N côté
Web Mercator. C'est une enveloppe de requête, pas une garantie de couverture de
chaque pixel. Un appel hors emprise retourne un PNG transparent valide sans
requête WMS ni masque côtier.

Une panne du fournisseur ou du masque requis renvoie 503, `no-store`, statut
`unavailable` et `Retry-After: 15`. Elle ne remplace pas une ancienne tuile par
un PNG transparent de succès. Le WMS temporise les reprises : 5 s après erreur
réseau, au moins 30 s après limitation ou erreur serveur.

Les travaux en file sans demandeur sont annulés. Un rendu déjà commencé garde
sa place jusqu'à sa fin pour borner les workers. Mapbox est limité à deux
requêtes simultanées par hôte ; les deux requêtes GeoJSON Dart ont leur budget
distinct. Ce plafond ne remplace pas les limites de débit du serveur.

Ces caches ne garantissent pas une conservation hors ligne illimitée. Les données
servent à l'affichage et ne remplacent pas les cartes nautiques officielles.
