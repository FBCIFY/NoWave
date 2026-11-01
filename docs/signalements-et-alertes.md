# Signalements et alertes

Un signalement associe une catégorie, une position confirmée et une heure d’observation. Il reste actif pendant 24 h à partir de cette observation. Les alertes servent à prévenir les autres comptes à proximité.

## Publier un point

En manuel, l’utilisateur place le point sur la carte, choisit la catégorie et peut ajouter un commentaire. La carte déplacée à l’écran ne change pas la position GPS utilisée pour recevoir les alertes.

Avec une photo, le parcours est plus long :

1. La capture attend une précision GPS de 50 m ou mieux et une orientation exploitable. Elle fige la position, le cap et l’inclinaison au déclenchement.
2. Le backend propose une position à partir de ces mesures et de la hauteur de caméra. Le mobile utilise une hauteur de 2,5 m par défaut : l’estimation reste approximative.
3. L’utilisateur confirme ou corrige le point sur la carte. Si le service d’estimation est indisponible, il peut placer le point lui-même en gardant sa photo.
4. Le mobile crée le signalement, puis envoie le JPEG préparé, sans EXIF, dans le stockage privé.

La position confirmée et l’heure d’observation restent les mêmes lors d’un réessai. Le même identifiant de publication évite de créer un deuxième signalement et une deuxième vague d’alertes.

Si l’upload échoue, le signalement reste publié. Le formulaire permet de renvoyer la même photo ou de terminer sans elle. Il ne crée ni brouillon persistant ni envoi différé après fermeture du parcours.
La lecture d’une photo passe par une URL temporaire de cinq minutes. Masquer la photo empêche les nouvelles URL ; les liens déjà émis expirent normalement.

## Recevoir une alerte

À la publication, PostGIS sélectionne les autres comptes actifs ayant activé les alertes. Leurs appareils doivent être actifs, posséder un token FCM et une position de précision comprise entre 0 et 50 m, à 10 NM (18 520 m) au plus du point signalé.
Le serveur utilise la dernière position enregistrée : ni son ancienneté ni le cap ne filtrent les destinataires. Déplacer la carte ou consulter un point éloigné ne rend pas le compte éligible dans cette zone.

Le signalement, l’historique des alertes et les tâches d’envoi sont enregistrés ensemble. L’historique garde la distance minimale parmi les appareils éligibles du compte.
Un worker revérifie l’éligibilité et l’expiration avant l’envoi. Les erreurs temporaires sont retentées jusqu’à expiration ; `sent` signifie que FCM a accepté le message. L’historique reste disponible même si le push échoue.

Ouvrir un push réutilise la carte principale. L’app relit le signalement avant de le sélectionner ; un point expiré ou retiré n’est plus accessible. Si une publication est en cours, la navigation attend au lieu de fermer le formulaire.

## Données visibles et modération

Le partage du pseudo, celui du bateau et les alertes sont trois préférences indépendantes, désactivées au départ. Les détails ordinaires respectent ces choix ; les lectures admin donnent accès aux informations nécessaires à la modération.
Pour le suivi GPS, le serveur ne conserve que la dernière position de chaque appareil, sans historique de navigation. La suppression du compte retire son profil et ses appareils ; ses signalements restent avec un auteur supprimé.

Un admin actif peut retirer ou restaurer un signalement, masquer sa photo, suspendre ou réactiver un compte. Chaque action demande un motif et écrit une entrée d’audit avec le changement.
Restaurer conserve l’expiration initiale et ne déclenche pas de nouvelle alerte. Suspendre un compte bloque les routes métier et l’exclut des destinataires d’alertes, sans retirer automatiquement ses signalements : leur modération reste séparée.
La modification et la suppression des signalements par leur auteur ne sont pas livrées. « Mes alertes » est l’historique des alertes reçues, pas celui des publications personnelles.
