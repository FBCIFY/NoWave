from app.application.ports.auth_provider import AuthProvider
from app.application.ports.user_repository import UserRepository


class DeleteUser:
    def __init__(
        self,
        user_repository: UserRepository,
        auth_provider: AuthProvider,
    ):
        self.user_repository = user_repository
        self.auth_provider = auth_provider

    def execute(self, firebase_uid: str) -> None:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        # SQL reste la première étape.
        #
        # Si une tentative précédente a déjà supprimé
        # le profil mais a échoué côté Firebase, la
        # suppression reprend directement côté Firebase.
        if user is not None:
            self.user_repository.delete(user)

        self.auth_provider.delete_identity(
            firebase_uid
        )
