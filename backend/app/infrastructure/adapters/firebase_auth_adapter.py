import firebase_admin
from firebase_admin import auth

from app.application.ports.auth_provider import AuthProvider


class FirebaseAuthAdapter(AuthProvider):
    def __init__(self):
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app()

    def verify_token(self, token: str) -> dict:
        return auth.verify_id_token(token)

    def delete_identity(self, firebase_uid: str) -> None:
        try:
            auth.delete_user(firebase_uid)
        except auth.UserNotFoundError:
            # Une tentative précédente peut avoir déjà
            # supprimé l'identité Firebase.
            return
