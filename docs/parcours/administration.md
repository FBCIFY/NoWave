# Parcours — Modération et administration web

**Référence :** `dev@6b54aa8` (19/10/2026).

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

Les pages HTML de modération sont distinctes des opérations ci-dessus et ne sont pas comptées dans les **28 opérations FastAPI déclarées** du chapitre API. Les formulaires administratifs requièrent session, protection CSRF et droits adaptés.

## Implémentation / validation

Code : `backend/app/api/routes/admin.py`, `backend/app/web/routes/admin_pages.py`, `backend/app/application/services/moderation.py`.

Tests présents : `backend/tests/api/test_admin_moderation.py`, `backend/tests/api/test_admin_reads.py`, `backend/tests/api/test_admin_web.py` et `backend/tests/api/test_admin_web_pages.py`. Refaire sur environnement autorisé la recette d'accès non administrateur, la traçabilité, les transitions d'état et le refus d'accès à une photo masquée. Ne pas recopier d'identifiants ni de clés réelles dans les preuves.