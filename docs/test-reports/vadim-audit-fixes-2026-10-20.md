# Corrections Vadim — audit du 19 octobre 2026

Branche : `fix/vadim-audit-2026-10-19`, créée depuis `dev@8fdb36c` après mise à jour.
Une branche commune pour la future PR. Le nouveau `dev@e708880`, qui contient
la PR marine #93, a ensuite été intégré localement par le merge `dcc0a5c`.
Aucune PR créée, aucun push, aucune fusion vers `dev`/`main` et aucun déploiement de production
effectués pendant cette tâche.

## Corrections réalisées

Chaque ticket possède un commit et un rapport individuel dans ce dossier.
« Corrigé » désigne ici le code et ses validations locales ; les essais natifs
restants sont indiqués dans chaque rapport. Les statuts Linear n'ont pas été
modifiés.

| Ticket | Correction | Commit |
|---|---|---|
| NW-175 | Badges visibles dès le zoom 9 | `9bae5d8` |
| NW-176 | Avertissement conservé après fermeture du bandeau | `5230480` |
| NW-177 | Intervalle minimal entre les tentatives d'envoi GPS | `c59f493` |
| NW-178 | Refus des précisions GPS négatives ou non finies | `3223f80` |
| NW-179 | Position courante dans les fiches d'alertes | `d708a33` |
| NW-180 | Information sur le GPS en arrière-plan dans le profil | `ea8fdeb` |
| NW-181 | Espaces intérieurs conservés dans les noms de profil | `7623889` |
| NW-184 | Suspension visuelle de la carte derrière un autre écran | `df297b0` |
| NW-185 | Contraste des contrôles cyan | `cdf64c5` |
| NW-186 | Mouvements réduits respectés par les transitions caméra | `513254f` |
| NW-188 | Conversion actuelle du point exigée avant publication | `51444c7` |
| NW-190 | Invalidation des anciennes intentions caméra | `3dc12f2` |
| NW-192 | Fraîcheur du GPS et des capteurs continus avant capture | `b9b0bde` |
| NW-193 | Reprise du relais après fin du flux GPS natif | `6197216` |
| NW-194 | Push lié au compte destinataire | `ef6cf17` |
| NW-195 | Erreurs de tuiles conservées pendant l'installation | `93ea8de` |
| NW-196 | Formulaire défilable avec texte agrandi et clavier | `dcdc68a` |

## Alignement cartographique et investigations

- [NW-187](NW-187.md) : choix existant confirmé par Vadim et vérifié sur Git :
  Mapbox conservé, PR #93 fusionnée dans `dev@e708880`. Documentation alignée
  et nouveau `dev` intégré à cette branche. Aucune réimplémentation de #93.
- [NW-197](NW-197.md) : ouverture et sélection du grand-angle `wide` observées
  sur iPhone 12 Pro. Essais de netteté annulés par Vadim (tempête, immeuble).
  Focus lointain et recette multi-appareils restent non validés. Outil prêt
  pour reprise ; aucun changement de caméra de production.
- [NW-201](NW-201.md) : mesure locale et trois comparaisons sur iPhone 12 Pro
  en mode profile réalisées. P95 UI Flutter en rotation de 2,63 à 2,98 ms,
  aucune frame mesurée au-delà du budget de 16,7 ms. Flux contrôlé, moteur
  Mapbox réel, couches marines vides locales. Aucune anomalie de fluidité
  démontrée dans ce périmètre ; aucune optimisation de production ajoutée.

## Validation globale finale

Les résultats ci-dessous portent sur les fixes réunis avec `dev@e708880` dans
`dcc0a5c`, avant l'alignement documentaire final de NW-187. Ils incluent les
nouveaux tests marins et les corrections de cette branche. Les validations
précédentes, avant cette intégration, étaient de 568 tests Flutter et 647 tests
API/unitaires serveur réussis ; elles ne sont pas additionnées aux résultats
ci-dessous.

| Contrôle | Résultat |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 191 fichiers, aucun changement requis |
| `flutter analyze --no-pub` | Aucun problème |
| `flutter test --no-pub --coverage --reporter expanded` | **650 tests réussis** |
| `pytest backend/tests/api backend/tests/unit -q` | **911 tests réussis, 1 ignoré** |
| `pytest backend/tests/database -q` | **275 tests réussis** |
| `ruff check backend deploy/hostinger mobile/tool` | Réussi |
| `git diff --check` | Réussi |

Les tests PostGIS ont utilisé le projet Docker temporaire `nowave-vadim-fixes`,
avec stockage temporaire et une base de test créée puis supprimée par la fixture.
Le conteneur et le réseau dédiés ont été nettoyés après validation. Aucun accès
aux données applicatives existantes ou à la production n'a été utilisé.

Les avertissements Starlette/httpx et Shapely (`oriented_envelope`) sont
présents, sans échec. Le test optionnel d'archives SHOM locales est ignoré en
leur absence. Les dépendances marines de #93 ont été installées depuis le
fichier de test verrouillé dans un environnement temporaire dédié. Aucun
renouvellement de dépendance n'a été ajouté par les fixes.
Les tests web et les audits d'images ne sont pas rejoués ici. La CI de la future
PR, la validation des images issues de #93 et la recette Android/iOS réelle
restent distinctes de ces contrôles locaux.

## Points de livraison

- NW-194 : déployer le worker qui renseigne `recipient_firebase_uid` avant la
  nouvelle version mobile. Les anciens pushes sans ce champ renvoient vers
  l'historique. Pas de migration SQL.
- NW-192 : seuils techniques centralisés, 15 secondes pour le GPS et 5 secondes
  pour les capteurs continus ; à éprouver en réception faible sur appareil.
- Les commits utilisent l'identité Git déjà configurée dans le dépôt et ne
  comportent aucune co-signature ajoutée.
