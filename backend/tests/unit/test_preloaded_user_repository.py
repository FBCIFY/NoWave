from unittest.mock import Mock

from app.api.dependencies.auth import reuse_current_user
from app.application.repositories.preloaded_user_repository import PreloadedUserRepository
from app.domain.user import User


def test_preloaded_profile_is_scoped_to_uid_and_invalidated_on_write():
    user = User(firebase_uid="first", username="first", email="first@test.fr")
    repository = Mock()
    wrapped = PreloadedUserRepository(repository, user)
    assert wrapped.get_by_firebase_uid("first") is user
    repository.get_by_firebase_uid.assert_not_called()
    assert wrapped.get_by_firebase_uid("other") is repository.get_by_firebase_uid.return_value
    repository.get_by_firebase_uid.assert_called_once_with("other")

    wrapped.update(user, fields={"username"})
    repository.update.assert_called_once_with(user, fields={"username"})
    assert wrapped.get_by_firebase_uid("first") is repository.get_by_firebase_uid.return_value


def test_claims_cannot_supply_a_trusted_preloaded_user():
    repository = Mock()
    identity = {"uid": "first", "user": {"role": "admin", "status": "active"}}
    assert reuse_current_user(identity, repository) is repository
