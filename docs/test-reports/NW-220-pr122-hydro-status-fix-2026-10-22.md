# NW-220 — Correction finale des statuts hydrographiques de la PR #122

Date : 22 octobre 2026. Dépôt : `FBCIFY/NoWave`. Branche : `feature/NW-220-satellite-bathymetry-colors`.

## État de la PR

Le HEAD local, la branche distante de suivi et le HEAD de la PR #122 sur GitHub ont été vérifiés à `47fe509ee75c9a78120535c5b3ef9b2dc497d11e`. La PR était ouverte. Aucun commit, push, merge ou déploiement n'a été effectué. Le rapport complémentaire déjà présent et non suivi (`NW-220-pr122-complementary-review-2026-10-22.md`) a été laissé intact.

## Audit 1 — Contrat producteur, API, consommateur

- `marine_tiles.py` produit `empty` pour une tuile de sondes sans entité fusionnée avec au moins un fournisseur, et `outside-coverage` lorsqu'aucun fournisseur ne couvre la tuile. Ce sont des résultats complets si aucun fournisseur n'a échoué. Le cache du service vaut 300 s sans échec et 15 s avec échec. Une indisponibilité totale ne devient pas une tuile vide : elle lève `ProviderUnavailable`.
- `map_tiles.py` renvoie ces statuts dans `X-NoWave-Marine-Status` pour les HTTP 200. Si `result.failures` est non vide, l'API renvoie toujours `degraded`, quel que soit `result.status`. L'indisponibilité totale des sondes donne un HTTP 503 avec `unavailable` et `no-store`. Les sondes HTTP 200 portent aussi `no-store` : le TTL pertinent dans l'application est celui de `MarineViewport`.
- Avant correction, `marine_viewport.dart` ne considérait complets que `ok`, `below-minzoom` et l'absence d'en-tête. Les HTTP 200 `empty` et `outside-coverage` entraient donc dans le chemin dégradé : TTL 15 s, retry à 16 s, et impossibilité de basculer atomiquement de Z12 vers Z13 lorsque les neuf nouvelles cellules étaient vides.

## Reproduction avant correction

Deux tests Flutter paramétrés séparément avec `X-NoWave-Marine-Status: empty` et `outside-coverage` ont échoué avant la modification de production. Dans chaque cas, après réception des neuf cellules Z13 vides, la géométrie surfacique Z12 `modeled-z12` restait affichée au lieu d'une collection vide. Les échecs figurent dans `/tmp/nw220-status-empty-before.log` et `/tmp/nw220-status-outside-before.log`.

## Correctif et tests après correction

`MarineViewport` classe maintenant `empty` et `outside-coverage` avec `ok` et `below-minzoom` comme réponses complètes. La classification des autres valeurs reste inchangée. Deux tests vérifient pour chaque nouveau statut : la bascule Z12 vers les neuf cellules Z13 vides, la disparition de l'ancienne surface dans `features()` et dans la source Mapbox, l'absence d'erreur, aucune nouvelle requête à 16 et 299 s, puis le renouvellement après 300 s. Deux tests supplémentaires vérifient que `degraded` et `partial` conservent l'ancienne surface, enregistrent neuf erreurs dégradées et relancent neuf requêtes après 16 s.

Les tests déjà présents couvrent les HTTP 503 et timeouts avec retry, les réponses partielles, la conservation des surfaces pendant les changements de zoom et les mouvements de caméra continus. Les tests existants de la couche hydrographique couvrent le fondu Z10–Z12, les courbes fixées à Z12 et les sondes visibles dès Z13. Ceux des sources contrôlent `marine-palette-3`; ceux du viewport et des ports contrôlent le recalcul des collisions portuaires.

## Audit 2 — Revue du diff et de la chaîne de bascule

La seconde revue a suivi le chemin `HTTP 200 → statut → snapshot.complete / expires → features() → _displayZoom`. Le diff de production ne change que l'ensemble des statuts complets. Il ne modifie ni le planificateur des requêtes, ni les sources, ni les couches, ni les collisions. Les neuf cellules de la nouvelle résolution doivent toutes avoir un snapshot complet et non expiré avant que `features()` change `_displayZoom`; une réponse `degraded` ou `partial` ne satisfait pas ce prédicat. Le service et la route empêchent également un échec fournisseur de sortir sous l'en-tête `empty` ou `outside-coverage`. `git diff --check` est propre.

Limite du contrat préexistant : l'absence d'en-tête reste acceptée comme réponse complète, notamment pour les clients ou tests historiques. L'API examinée émet toujours l'en-tête pour ses réponses HTTP 200.

## Validations

| Contrôle | Résultat |
| --- | --- |
| Tests Flutter ciblés des quatre statuts | 4 réussis |
| Fichier de tests `marine_viewport_test.dart` après formatage | 17 réussis |
| Suite Flutter complète, après la dernière modification des tests | 807 réussis |
| `flutter analyze` | Aucun problème |
| Tests backend ciblés (`test_marine_viewport.py`, `test_marine_tiles.py`, API `test_marine_tiles.py`) | 44 réussis ; un avertissement de dépréciation Starlette |
| `dart format --output=none --set-exit-if-changed lib test` | 226 fichiers contrôlés, aucun changement requis |
| `git diff --check` | Réussi |

Le test existant de mouvement continu a échoué deux fois lors d'exécutions isolées du fichier complet sous charge, avec des compteurs temporels différents. Il a réussi lancé seul, puis dans la suite Flutter complète de 807 tests. Ses assertions et son code n'ont pas été modifiés ; cette instabilité temporelle préexistante reste à surveiller.

## Fichiers modifiés et verdict

- `mobile/lib/features/map/data/marine_viewport.dart` : classification des statuts complets.
- `mobile/test/features/map/data/marine_viewport_test.dart` : quatre cas de régression.
- `docs/test-reports/NW-220-pr122-hydro-status-fix-2026-10-22.md` : présent rapport.

**Verdict : prêt pour une nouvelle revue de PR.** Le correctif et les validations sont locaux, sans publication. La seule réserve observée est la sensibilité au temps du test de mouvement continu existant ; la validation complète finale est verte.
