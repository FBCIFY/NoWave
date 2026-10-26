# Parcours — Modération et centre de surveillance maritime NW-244

**Référence du code audité :** `dev@c3172ad` (23/10/2026, PR #132) ; le déploiement réel doit être vérifié séparément.

## Objectif

Le back-office administratif permet à un compte autorisé de consulter les signalements et les comptes, de modérer un signalement ou une photo et de retrouver les actions enregistrées. La modification par l'auteur du signalement, non livrée, ne doit pas être confondue avec les actions d'administration.

## API de modération

| Opération | Usage |
| --- | --- |
| `GET /api/v1/admin/reports` | Lister les signalements |
| `GET /api/v1/admin/reports/{report_id}` | Lire le détail pour modération |
| `PATCH /api/v1/admin/reports/{report_id}` | Restaurer un signalement suivant les règles de modération |
| `DELETE /api/v1/admin/reports/{report_id}` | Retirer un signalement en tant qu'administrateur |
| `PATCH /api/v1/admin/reports/{report_id}/photo` | Masquer une photo |
| `GET /api/v1/admin/users` | Lister les comptes |
| `PATCH /api/v1/admin/users/{user_id}` | Suspendre ou réactiver un compte |
| `GET /api/v1/admin/moderation-actions` | Lire les traces d'audit |

Les pages HTML et les lectures JSON `/admin/data` sont distinctes des opérations API listées ci-dessus : elles sont exclues de l'inventaire `/api/v1`. Les formulaires administratifs requièrent session, protection CSRF et droits adaptés.

## Centre de surveillance et parcours navigateur (NW-244)

Les pages `/admin` restent rendues par **FastAPI/Jinja** ;
les formulaires de modération exigent motif, confirmation, CSRF
et une session d'administrateur actif. Les scripts locaux
**Mapbox GL JS 3.32.0** assurent le globe de connexion, la carte,
les clusters, les panneaux de signalements et d'utilisateurs.
Les pages `/admin/reports`, `/admin/reports/{id}`, `/admin/users`
et `/admin/audit` restent accessibles en HTML sans carte.

La carte de surveillance est en projection Mercator, nord en haut,
avec un centre initial `[-30, 24]` au zoom `2.4`. Le fond mondial
GEBCO 2026 est un raster précalculé, servi par Nginx jusqu'à Z6,
et s'estompe entre Z6 et Z8. La carte administrative n'ajoute pas
les bouées, sondes ou isobathes de l'application mobile.
Les marqueurs `marine_animal` (cyan), `obstruction` (orange)
et `pollution` (violet) sont regroupés en clusters rouges.

### Lectures JSON du navigateur

| Route protégée | Contrat |
|---|---|
| `GET /admin/data/reports?west=…&south=…&east=…&north=…` | `FeatureCollection` GeoJSON et booléen `truncated` |
| `GET /admin/data/reports/{target_id}` | Détail et photo autorisée du signalement |
| `GET /admin/data/users?page=1&status=…&search=…` | Recherche/filtre serveur, `items`, `page`, `pages`, `total` |
| `GET /admin/data/users/{user_id}/reports?page=1` | `items`, `page`, `has_more`, 20 résultats maximum par page |

Ces quatre routes exigent une session d'administrateur actif
et répondent avec `Cache-Control: no-store`. Elles ne sont
**pas** des opérations de modération et ne constituent pas
des endpoints de l'API `/api/v1/admin`.

Le MVP limite l'affichage à **1 000 signalements par emprise**.
Une ligne supplémentaire est lue pour identifier la troncature :
l'interface affiche alors « Affichage partiel ».
Les clusters et compteurs sont non exhaustifs si `truncated=true`.
La recherche utilisateurs est paginée par 20 ; les signalements
du compte utilisent `has_more`, avec annulation des lectures obsolètes.

### Sécurité et limites de recette

Le cookie navigateur `__Host-nowave_admin_session` est `HttpOnly`,
`Secure`, `SameSite=Strict` et expire après huit heures. Chaque
requête authentifiée vérifie à nouveau la session et le profil.
Les écritures de modération restent transactionnelles et auditées.
Le jeton `MAPBOX_PUBLIC_TOKEN`, public et restreint aux domaines
de l'administration, doit être injecté via la configuration externe.
En son absence, listes et formulaires restent accessibles.
La CSP Nginx permet scripts locaux, worker `blob:`, connexions Mapbox
et images Scaleway sur les domaines autorisés, sans scripts distants
ni `unsafe-eval`.

La CI exécute les tests navigateur Playwright avec PostGIS isolé
et fournisseurs externes simulés ; les tests Mapbox réels demandent
un jeton public local et ne sont pas inclus au job standard.
Une recette Firebase, Mapbox et Scaleway réelle reste à conduire
avec des comptes et données **de test**, jamais par modération
de données de production.

Références : [README web](../../backend/app/web/README.md),
[tests navigateur](../../backend/tests/browser/README.md) et
[rapport NW-244](../test-reports/NW-244-post-merge.md).
## Implémentation / validation

Code : `backend/app/api/routes/admin.py`, `backend/app/web/routes/admin_pages.py`, `backend/app/application/services/moderation.py`.

Tests présents : `backend/tests/api/test_admin_moderation.py`, `backend/tests/api/test_admin_reads.py`, `backend/tests/api/test_admin_web.py` et `backend/tests/api/test_admin_web_pages.py`. Refaire sur environnement autorisé la recette d'accès non administrateur, la traçabilité, les transitions d'état et le refus d'accès à une photo masquée. Ne pas recopier d'identifiants ni de clés réelles dans les preuves.