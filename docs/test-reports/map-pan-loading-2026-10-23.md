# Blocage cartographique lors de déplacements rapides — 23 octobre 2026

Observation de la version serveur `d0af9c6` et de l'iPhone équipé de la version
`2026102309`. Le correctif se trouve sur `codex/fix-map-pan-loading`.

## Constats en production avant correction

Logs Nginx et API lus par SSH, sans modification du serveur. Les chiffres
concernent l'ensemble des requêtes cartographiques reçues dans ces fenêtres ;
ils ne sont pas attribués individuellement à une session mobile.

Sur la fenêtre du 23 octobre, de 14:29:21 à 14:49:21 (Europe/Paris) :

| Famille | Requêtes | Succès 200 | Annulations 499 | Autres erreurs |
| --- | ---: | ---: | ---: | --- |
| Bathymétrie | 2 949 | 1 606 | 16 | 1 323 × 503, 4 × 504 |
| Fond mondial GEBCO | 794 | 794 | 0 | aucune |
| Signalements MVT | 4 502 | 1 798 | 2 704 | aucune |
| Objets marins GeoJSON | 2 373 | 1 989 | 384 | aucune |
| Infrastructures portuaires | 1 439 | 553 | 886 | aucune |

Le p95 serveur de la bathymétrie atteint 16,498 secondes ; certaines tuiles sont
redemandées quinze fois. Les logs API montrent notamment 668 avertissements
« render queue deadline exceeded », 630 indisponibilités EMODnet et 28 délais
de réponse dépassés. Certaines compositions de masques côtiers durent plus de
vingt secondes. Un 499 signifie ici une requête abandonnée par le client, et ne
prouve pas un crash.

Une seconde fenêtre de cinq minutes montre 158 réponses 429 : 86 rejets de débit
sur les signalements et 72 rejets de connexions sur les couches marines. Les
conteneurs API et Web n'ont ni redémarré ni subi d'OOM. Lors de la première
mesure, l'API utilise environ 211 Mio sur 768 Mio. L'application tourne encore
sur l'iPhone lors du contrôle ; cela n'exclut pas un incident antérieur.

Ces observations désignent une accumulation de rendus et des reprises répétées
de tuiles, avec saturation ponctuelle des limites du proxy. Elles ne prouvent
pas un crash du processus de rendu natif.

## Correctif

- Plafond HTTP natif Mapbox à douze requêtes simultanées par hôte.
- Détection des abandons HTTP et suppression des rendus encore en file quand
  aucun demandeur ne les attend ; partage des rendus utiles conservé.
- Délai partagé de reprise EMODnet après erreur réseau, limitation ou panne.
- En cas d'indisponibilité des détails raster, superposition transparente
  explicitement marquée indisponible et cache HTTP limité à quinze secondes.
  Le fond mondial reste visible. Aucun enregistrement de ce repli dans le cache
  normal de vingt-quatre heures ; les objets et profondeurs gardent leur contrat.

## Validation et limites

La suite API/unités Python passe : 1 096 tests réussis, 2 ignorés. Ruff et
`git diff --check` passent. Les tests couvrent le retrait d'une file abandonnée,
la conservation des demandeurs partagés, le plafond des workers, le délai de
reprise fournisseur et le retour des vrais détails après une panne.

Les 24 tests Flutter ciblés passent, dont le passage du plafond au service HTTP
natif, une erreur de configuration native et les régressions de caméra/viewport.
L'analyse Flutter passe sans problème.
La suite Flutter complète passe également : 903 tests réussis.

Le correctif n'a pas encore été déployé ni installé sur l'iPhone. Le recul réel
des 429 et le comportement visuel pendant une longue série de glissements
restent à mesurer après livraison ; les tests avec doubles ne mesurent pas le
GPU ni la réactivité du SDK natif.
