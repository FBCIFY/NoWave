# Architecture

Le mobile et le site parlent à la même API FastAPI. L’admin est rendu par ce backend en HTML/Jinja. Les workers utilisent la même image que l’API, mais tournent dans des processus séparés. PostgreSQL/PostGIS contient les données métier ; les JPEG sont dans un bucket Scaleway privé.

Flutter garde la caméra, le GPS, les capteurs et les interactions Mapbox sur le téléphone. Il envoie les mesures et le point confirmé au serveur. Les règles d’accès, l’expiration des signalements et le choix des destinataires d’alertes restent côté backend.

Pour retrouver une responsabilité dans le code :

- `mobile/lib/features/` contient les parcours compte, carte, signalement, caméra et alertes. `mobile/lib/core/` regroupe API, appareil, capteurs et notifications.
- `web/` compile le site public et les assets cartographiques partagés avec l’admin. En production, Nginx sert ce build et les tuiles GEBCO.
- `backend/app/api/` valide les entrées et construit les réponses JSON. `backend/app/web/` gère les pages, sessions et formulaires admin.
- `backend/app/application/services/` exécute les opérations : créer un compte, publier, envoyer une photo, modérer. `domain/` porte les états et les règles de validation.
- `backend/app/infrastructure/` accède à PostgreSQL, Firebase, Scaleway et aux fournisseurs marins. Les repositories exécutent les écritures SQL et leurs transactions.

Firebase gère l’identité, le mot de passe et les tokens. Le profil NoWave associe cet UID au pseudo, au rôle, au statut et aux préférences. Un token valide ne suffit pas pour une opération métier : l’API relit aussi le profil actif. Les lectures de profil et les opérations de nettoyage du compte ont leurs exceptions, détaillées dans les contrats API.

L’admin web utilise un cookie de session Firebase, revérifié avec contrôle de révocation et lecture du profil à chaque requête. Les formulaires vérifient aussi le CSRF. Le site public ne reçoit ni les e-mails, ni les photos, ni les données de bateau ; le pseudo suit le consentement de l’auteur.

## Ce qui est stocké

Les migrations Alembic décrivent le schéma du namespace `nowave`. Les relations importantes sont :

- `users` porte le profil et les consentements. `boats` contient au plus un bateau par compte.
- `devices` identifie les installations, leur token FCM et leur état actif. `device_positions` garde une seule position par appareil, pas un trajet.
- `reports` garde l’auteur, la catégorie, le point final, l’observation, l’expiration et la version. Les coordonnées utilisent WGS84 ; les distances sont calculées avec PostGIS.
- `report_positioning` conserve les mesures et l’estimation du mode photo. `report_photos` garde l’état d’upload, les métadonnées et la clé objet, pas les octets du JPEG.
- `alert_history` contient un instantané par utilisateur, signalement et version. `notifications` contient une tâche FCM par appareil, signalement et version.
- `moderation_actions` enregistre l’action, l’admin, la cible et le motif. `map_cache_revision` sert à invalider les tuiles après une écriture.

Supprimer un compte efface son bateau, ses appareils et son historique d’alertes. Ses signalements restent, avec `author_id = NULL`. Le service supprime d’abord le profil SQL puis l’identité Firebase ; une nouvelle tentative peut reprendre la seconde étape.

Les sources marines et leurs snapshots ne sont pas des tables métier PostgreSQL. Ils passent par des fournisseurs HTTP, des caches locaux et le rendu mobile. Le détail est dans [la couche marine](couche-marine.md).

## Où passent les écritures

À la publication, le service valide le compte et le signalement. Le repository écrit le signalement, l’historique d’alertes et les tâches FCM dans une seule transaction. Une clé unique sur l’auteur et `client_report_id` évite le doublon après une réponse perdue. Le worker ne voit les tâches qu’après commit.

La carte mobile lit les signalements actifs en tuiles MVT produites depuis PostGIS. Le site public utilise une lecture paginée par curseur. Le détail est relu auprès de l’API à l’ouverture : une tuile ou un push déjà reçu ne décide pas si un signalement est encore accessible.

Les règles de publication, d’envoi et de modération sont dans [signalements et alertes](signalements-et-alertes.md). Les formats HTTP restent dans [les contrats API](contrats-api.md).
