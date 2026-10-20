# Parcours — Alertes de proximité et ouverture FCM

**Référence :** `dev@6b54aa8` (19/10/2026). Tickets : NW-116, NW-117, NW-125, NW-157, NW-163.

## Flux

1. L'utilisateur active sa préférence d'alertes dans son profil et autorise les notifications au niveau du système. Ces consentements sont indépendants.
2. L'application enregistre son installation et sa dernière position éligible via les routes `/api/v1/devices/current`. Le backend utilise PostGIS pour les cibles dans le rayon de proximité prévu par les règles métier.
3. La création d'un signalement valide déclenche la préparation des alertes. Un worker vérifie à nouveau l'éligibilité, la version et l'expiration avant l'envoi vers Firebase Cloud Messaging.
4. Une alerte reçue ou consultée dans l'historique peut ouvrir la **carte principale** sur le signalement identifié, avec cadrage adapté et relecture du détail par l'API. Si le GPS est indisponible, l'affichage se replie sur le signalement seul ; aucun point n'est inventé.
5. `GET /api/v1/users/me/alerts` renvoie l'historique des **alertes reçues** avec pagination. Il ne s'agit pas de l'historique des signalements créés par l'utilisateur.

## Points de vigilance

- `sent` côté worker prouve l'acceptation du message par FCM, pas sa réception par l'appareil.
- Les taps FCM en avant-plan, arrière-plan et démarrage à froid constituent trois scénarios de test distincts.
- Le marqueur sélectionné peut être affiché indépendamment du chargement des tuiles MVT ; son icône doit être vérifiée par rapport à la catégorie métier avant d'affirmer une conformité visuelle.
- Une réponse ancienne, un compte modifié, une déconnexion ou un brouillon de publication ne doit pas entraîner une navigation parasite.

## Implémentation / tests

Code : `backend/app/application/services/send_notifications.py`, `backend/app/application/services/list_my_alerts.py`, `backend/app/api/routes/users.py`, `mobile/lib/features/alerts/`, `mobile/lib/core/notifications/`, `mobile/lib/features/map/`.

Tests : `backend/tests/api/test_my_alerts.py`, `backend/tests/database/test_notification_worker.py`, `mobile/test/features/alerts/`. Un [rapport de tests NW-163](../test-reports/NW-163.md) décrit des tests automatisés ; il précise que la réception FCM/APNs et le rendu Mapbox sur appareils réels restent à confirmer. Ces niveaux ne doivent pas être confondus dans la matrice.