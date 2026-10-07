import pytest
from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.domain.boat import Boat, BoatType
from app.domain.user import User
from app.main import app


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if (
            self.user is not None
            and self.user.firebase_uid == firebase_uid
        ):
            return self.user

        return None


class FakeBoatRepository:
    def __init__(self, boat=None):
        self.boat = boat

    def get_by_user_id(self, user_id):
        if (
            self.boat is not None
            and self.boat.user_id == user_id
        ):
            return self.boat

        return None

    def save(self, boat):
        self.boat = boat
        return boat

    def update(self, boat):
        self.boat = boat
        return boat

    def delete(self, boat):
        if self.boat is boat:
            self.boat = None


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def make_user():
    return User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )


def setup_repositories(
    monkeypatch,
    user_repository,
    boat_repository,
):
    monkeypatch.setattr(
        "app.api.routes.boats.PostgreSQLUserRepository",
        lambda: user_repository,
    )

    monkeypatch.setattr(
        "app.api.routes.boats.PostgreSQLBoatRepository",
        lambda: boat_repository,
    )


def test_create_my_boat(monkeypatch):
    user = make_user()

    user_repository = FakeUserRepository(user)
    boat_repository = FakeBoatRepository()

    setup_repositories(
        monkeypatch,
        user_repository,
        boat_repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me/boat",
        json={
            "boat_type": "voilier",
            "name": "Ulysse",
            "flag_country": "fr",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 201

    data = response.json()

    assert data["boat_type"] == "voilier"
    assert data["name"] == "Ulysse"
    assert data["flag_country"] == "FR"

    assert boat_repository.boat is not None
    assert boat_repository.boat.user_id == user.id


def test_create_second_boat_returns_409(monkeypatch):
    user = make_user()

    existing_boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
    )

    user_repository = FakeUserRepository(user)
    boat_repository = FakeBoatRepository(existing_boat)

    setup_repositories(
        monkeypatch,
        user_repository,
        boat_repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me/boat",
        json={
            "boat_type": "catamaran",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert (
        response.json()["error"]["code"]
        == "boat_already_exists"
    )


def test_get_my_boat(monkeypatch):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(boat),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me/boat",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["name"] == "Ulysse"
    assert data["boat_type"] == "voilier"
    assert data["flag_country"] == "FR"


def test_get_missing_boat_returns_404(monkeypatch):
    user = make_user()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me/boat",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "boat_not_found"
    )


def test_update_my_boat_partially(monkeypatch):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    boat_repository = FakeBoatRepository(boat)

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        boat_repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me/boat",
        json={
            "name": "NoWave",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["name"] == "NoWave"
    assert data["boat_type"] == "voilier"
    assert data["flag_country"] == "FR"


def test_update_can_clear_optional_fields(monkeypatch):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(boat),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me/boat",
        json={
            "name": None,
            "flag_country": None,
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["name"] is None
    assert data["flag_country"] is None
    assert data["boat_type"] == "voilier"


def test_update_boat_type_cannot_be_null(monkeypatch):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
    )

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(boat),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me/boat",
        json={
            "boat_type": None,
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_delete_my_boat(monkeypatch):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
    )

    boat_repository = FakeBoatRepository(boat)

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        boat_repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.delete(
        "/api/v1/users/me/boat",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 204
    assert response.content == b""
    assert boat_repository.boat is None


def test_delete_missing_boat_returns_404(monkeypatch):
    user = make_user()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.delete(
        "/api/v1/users/me/boat",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "boat_not_found"
    )


def test_create_boat_rejects_invalid_type(monkeypatch):
    user = make_user()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(),
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me/boat",
        json={
            "boat_type": "yacht",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_create_boat_rejects_invalid_flag_country(
    monkeypatch,
):
    user = make_user()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me/boat",
        json={
            "boat_type": "voilier",
            "flag_country": "12",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_boat_route_requires_authentication():
    app.dependency_overrides.clear()

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me/boat",
    )

    assert response.status_code == 401


def test_get_boat_without_user_profile_returns_404(
    monkeypatch,
):
    setup_repositories(
        monkeypatch,
        FakeUserRepository(),
        FakeBoatRepository(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me/boat",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "user_not_found"
    )

@pytest.mark.parametrize(
    "flag_country",
    [
        123,
        True,
        {"code": "FR"},
    ],
)
def test_create_boat_rejects_non_text_flag_country(
    monkeypatch,
    flag_country,
):
    user = make_user()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me/boat",
        json={
            "boat_type": "voilier",
            "flag_country": flag_country,
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422

    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )


@pytest.mark.parametrize(
    "flag_country",
    [
        123,
        True,
        {"code": "FR"},
    ],
)
def test_update_boat_rejects_non_text_flag_country(
    monkeypatch,
    flag_country,
):
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        flag_country="FR",
    )

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        FakeBoatRepository(boat),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me/boat",
        json={
            "flag_country": flag_country,
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422

    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )
