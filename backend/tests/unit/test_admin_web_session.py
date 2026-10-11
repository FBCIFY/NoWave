from datetime import timedelta

import pytest

from app.application.services.access_control import resolve_active_admin
from app.application.services.admin_web_session import (
    SESSION_DURATION,
    AdminWebSession,
)
from app.domain.errors import (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    InvalidCredentialsError,
    InvalidSessionError,
    UserNotFoundError,
)
from app.domain.user import User, UserRole, UserStatus


IDENTITY = {
    "uid": "firebase-admin-1",
    "email": "admin@nowave.test",
    "email_verified": True,
}


class FakeWebAuthProvider:
    def __init__(self, identity=None, sign_in_error=None, session_error=None):
        self.identity = identity or IDENTITY
        self.sign_in_error = sign_in_error
        self.session_error = session_error
        self.created_sessions = []

    def sign_in_with_password(self, email, password):
        if self.sign_in_error:
            raise self.sign_in_error
        return "id-token"

    def verify_id_token(self, id_token):
        assert id_token == "id-token"
        return self.identity

    def create_session_cookie(self, id_token, expires_in):
        self.created_sessions.append((id_token, expires_in))
        return "session-cookie"

    def verify_session_cookie(self, session_cookie):
        if self.session_error:
            raise self.session_error
        assert session_cookie == "session-cookie"
        return self.identity


class FakeUserRepository:
    def __init__(self, user):
        self.user = user
        self.reads = 0

    def get_by_firebase_uid(self, firebase_uid):
        self.reads += 1
        if self.user and self.user.firebase_uid == firebase_uid:
            return self.user
        return None


def make_user(role=UserRole.ADMIN, status=UserStatus.ACTIVE):
    return User(
        firebase_uid="firebase-admin-1",
        username="admin",
        email="admin@nowave.test",
        role=role,
        status=status,
    )


def test_sign_in_creates_session_for_active_admin():
    provider = FakeWebAuthProvider()
    session = AdminWebSession(provider, FakeUserRepository(make_user()))

    assert session.sign_in("admin@nowave.test", "secret") == "session-cookie"
    assert provider.created_sessions == [("id-token", SESSION_DURATION)]


def test_session_lasts_eight_hours():
    assert SESSION_DURATION == timedelta(hours=8)


@pytest.mark.parametrize(
    ("user", "identity", "error"),
    [
        (make_user(role=UserRole.USER), IDENTITY, AdminRequiredError),
        (make_user(status=UserStatus.SUSPENDED), IDENTITY, InactiveUserError),
        (None, IDENTITY, UserNotFoundError),
        (
            make_user(),
            {**IDENTITY, "email_verified": False},
            EmailNotVerifiedError,
        ),
    ],
)
def test_sign_in_refused_creates_no_session(user, identity, error):
    provider = FakeWebAuthProvider(identity=identity)
    session = AdminWebSession(provider, FakeUserRepository(user))

    with pytest.raises(error):
        session.sign_in("admin@nowave.test", "secret")

    assert provider.created_sessions == []


def test_sign_in_propagates_invalid_credentials():
    provider = FakeWebAuthProvider(
        sign_in_error=InvalidCredentialsError("invalid email or password")
    )
    session = AdminWebSession(provider, FakeUserRepository(make_user()))

    with pytest.raises(InvalidCredentialsError):
        session.sign_in("admin@nowave.test", "wrong")

    assert provider.created_sessions == []


def test_authenticate_returns_admin():
    admin = make_user()
    session = AdminWebSession(FakeWebAuthProvider(), FakeUserRepository(admin))

    assert session.authenticate("session-cookie") is admin


def test_authenticate_rejects_admin_suspended_after_sign_in():
    session = AdminWebSession(
        FakeWebAuthProvider(),
        FakeUserRepository(make_user(status=UserStatus.SUSPENDED)),
    )

    with pytest.raises(InactiveUserError):
        session.authenticate("session-cookie")


def test_authenticate_propagates_invalid_session():
    session = AdminWebSession(
        FakeWebAuthProvider(
            session_error=InvalidSessionError("invalid admin session")
        ),
        FakeUserRepository(make_user()),
    )

    with pytest.raises(InvalidSessionError):
        session.authenticate("session-cookie")


def test_resolve_active_admin_reads_profile_once():
    repository = FakeUserRepository(make_user())

    resolve_active_admin(IDENTITY, repository)

    assert repository.reads == 1
