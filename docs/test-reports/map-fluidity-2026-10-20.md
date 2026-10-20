# NoWave : fluidité de la carte, 20 octobre 2026

Branche `map-fluidity`, créée depuis `dev` à
`06b2eea90bb2203b3d50d09fc03866ed5bee7cfb`. GitHub `dev` et l'API publique
`https://api.no-wave.fr/version` renvoient encore cette révision lors du contrôle
du 20 octobre. Aucun déploiement du backend modifié n'a été effectué.

## Builds et réglages

| Build | Source | Usage |
| --- | --- | --- |
| 2026102001 | dev `06b2eea` | Référence, release iOS et Android |
| 2026102002 | map-fluidity, modifications locales | Première itération |
| 2026102003 | map-fluidity, modifications locales | Marqueurs PNG, cadrage court, iOS profile normal installé |
| 2026102004 | map-fluidity, modifications locales | Clic marqueur robuste, protection contre GPS tardif, relâchement iOS assoupli |

Chaque installation conserve l'identifiant d'application et les données. Le
numéro est visible dans le profil. Pour les mesures, comparer deux builds profile
avec la même configuration et le même écran. Ne pas comparer un debug à un release.

Le serveur Wi-Fi est limité au dossier `/tmp/nowave-map-fluidity-distribution`.
L'index et le QR pointent vers `http://10.6.1.107:8765/` ; le téléphone doit être
sur le même réseau. Les APK et leurs empreintes identifient précisément les fichiers
distribués. Le QR reste identique lorsque l'index change.

Les mouvements sous les doigts restent natifs : déplacement sur deux axes,
rotation, pincement et translation simultanés. La rotation et le pincement n'ont
plus d'inertie après relâchement. Sur iOS, le facteur natif de décélération vaut
0,988 dans 04 (0,97 dans 03, jugé trop brusque). Sur Android, une animation native
de relâchement limitée à 200 ms plafonne la vitesse à 1 000 dp/s et ralentit avec
une courbe cubique. Un nouveau toucher annule l'animation. Ces valeurs restent à
calibrer sur les appareils ; la durée réelle d'inertie iOS dépend de la vitesse.

Le zoom d'un regroupement passe de 500 à 240 ms. Le cadrage d'une sélection dure
240 à 500 ms selon déplacement et changement de zoom. L'orientation actuelle est
préservée. La réduction des animations est respectée.

## Cadrage et marqueurs

- Clic sur un marqueur : charge sa fiche, mesure la place occupée, puis cadre le
  report seul au-dessus de la fiche. La mesure est refaite après chargement même
  sans changement de hauteur. Un événement tactile iOS reçu après le callback
  natif de sélection ne doit pas annuler ce même clic.
- Notification et Mes alertes : cadrent le report et le GPS récent ensemble.
  GPS absent ou périmé : report seul, avec information de repli. Le zoom à deux
  points est plafonné à 17 pour conserver du contexte lorsque les points coïncident.
- Un geste ou une nouvelle sélection invalide les calculs précédents. Un GPS
  initial reçu tardivement ne reprend pas le suivi après une sélection.
- Fermer la fiche retire son padding sans imposer un second déplacement animé.

Le bandeau « Signalements indisponibles » provenait d'une erreur native de
décodage des images : les marqueurs étaient fournis en RGBA brut alors que les
adaptateurs de cette version du SDK attendent des données encodées. Le passage
en PNG corrige les marqueurs de tuiles et le repère sélectionné. La couche a été
confirmée installée dans l'application normale iPhone et les requêtes de tuiles
reports sont revenues en HTTP 200. Le token Mapbox est présent et le style répond
HTTP 200 : ce défaut n'exigeait pas un nouveau token de configuration.

Les sources marines ont aussi produit des 429/503 pendant l'observation du VPS.
Ce problème distinct mérite une analyse de cache et de charge.

## Pôles et mesures

Le prototype natif, sur iPhone réel, avec `ConstrainMode.NONE`, demande une
latitude de ±89,999°, puis enchaîne 80 déplacements natifs dans chaque hémisphère.
La caméra s'arrête à ±85,05112877980663°. Aucun raccord artificiel des pôles n'a
été intégré. Un globe dédié reste séparé : estimation indicative de 1–2 jours
pour une faisabilité, puis plusieurs semaines pour les gestes, le raccord au
zoom rapproché, l'accessibilité et la validation des deux plateformes.

`mobile/tool/map_motion_probe.dart` est un outil de diagnostic profile distinct.
Il enregistre réaction, dernier événement caméra, délai après relâchement,
durées Flutter UI/raster et rendu Mapbox. Il ne doit pas remplacer l'interface
normale pendant les essais de l'utilisateur.

Les échantillons exploratoires de `test-results/map-fluidity/iphone-probe.json`
ont été pris sur une carte de taille incorrecte et avec une session interrompue.
Ils ne valident ni le ressenti ni les gains de l'application entière. Les essais
500/300 ms montrent environ 204 ms de différence médiane sur deux essais par
durée, mais le réglage final de 240 ms n'a pas de mesure comparative complète.
Aucun gain réel d'inertie iOS/Android n'est annoncé comme acquis.

## Notification ponctuelle

`backend/tools/send_test_notification.py` s'exécute dans l'environnement backend :

```sh
python backend/tools/send_test_notification.py \
  --user-id USER_UUID --installation-id INSTALLATION_UUID --report-id REPORT_UUID \
  --allow-own-report --dry-run
```

Le mode par défaut est une simulation en transaction SQL de lecture seule, sans
initialisation FCM. Il vérifie compte actif et consentement, appareil appartenant
au compte, token, report actif et position de moins de cinq minutes. L'option
`--allow-own-report` est réservée à cet outil : le worker automatique continue
d'exclure l'auteur.

Après simulation réussie, remplacer `--dry-run` par `--send` envoie une seule
notification à l'installation choisie avec le vrai format FCM. L'outil crée ou
réutilise l'historique de Mes alertes avant l'envoi, sans créer de travail pour le
worker. Une réponse FCM acceptée ne prouve pas la présentation par iOS/Android.
Aucun token ni préférence du téléphone n'est imprimé.

La première simulation distante a refusé une position trop ancienne. Lors du
dernier contrôle, aucun report n'était encore actif. Aucun push réel n'a donc
été envoyé. Un nouveau report et un GPS récent sont nécessaires.

## Validation et travail restant

- Analyse statique Flutter : aucune anomalie.
- Suite Flutter : 658 tests réussis, dont sélection successive, tap natif suivi
  d'un événement tactile tardif, fiche chargée lentement, GPS tardif, orientation,
  expiration, réduction des animations et protection du brouillon.
- Backend : 59 tests unitaires notifications et 2 tests SQL de l'outil réussis.
  Les tests SQL vérifient l'installation ciblée et l'historique idempotent, sans
  création de tâches pour le worker.
- À valider par essais physiques : nouveau relâchement iOS, clic de marqueur en
  04, Android, interruption pendant les gestes combinés et comportement aux
  hautes latitudes. Installation et compilation ne prouvent pas ces résultats.
- À compléter avec un report actif : notification au premier plan, arrière-plan,
  démarrage à froid et ouverture du même report depuis Mes alertes.
- À mesurer en plein écran : réaction, inertie, cadrage et frames lentes, sur les
  deux appareils, réseau stable puis lent, avec répétitions comparables.

Axes suivants fondés sur le code observé : réduire le travail des événements
caméra (synchronisation globe, étiquettes, halo et effets), stabiliser les
marqueurs entre zooms, conserver le point sous les doigts, et assurer la
continuité visuelle fiche/carte. Un benchmark de reconstructions ne suffit pas
à établir les performances du rendu Mapbox natif.
