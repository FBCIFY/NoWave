from app.application.ports.user_repository import UserRepository
from app.domain.user import User


class PreloadedUserRepository(UserRepository):
    """Reuse the authenticated profile for this request only, never across requests."""

    def __init__(self, repository: UserRepository, user: User):
        self.repository = repository
        self.user = user

    def get_by_firebase_uid(self, firebase_uid: str) -> User | None:
        if self.user is not None and self.user.firebase_uid == firebase_uid:
            return self.user
        return self.repository.get_by_firebase_uid(firebase_uid)

    def get_by_username(self, username: str) -> User | None:
        return self.repository.get_by_username(username)

    def save(self, user: User) -> User:
        self.user = None
        return self.repository.save(user)

    def update(self, user: User, fields: set[str] | None = None) -> User:
        self.user = None
        return self.repository.update(user, fields=fields)

    def delete(self, user: User) -> None:
        self.user = None
        self.repository.delete(user)
