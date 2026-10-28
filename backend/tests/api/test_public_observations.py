from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.api.routes.public_observations import get_public_observation_reader
from app.application.ports.public_observation_reader import PublicObservation
from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.report import ReportCategory
from app.main import app


NOW = datetime.now(UTC)


def observation(identifier=1, **changes):
    return PublicObservation(**{
        "id": UUID(int=identifier), "category": ReportCategory.MARINE_ANIMAL,
        "longitude": -28.7, "latitude": 38.33,
        "observed_at": NOW - timedelta(minutes=identifier),
        "expires_at": NOW + timedelta(hours=23), **changes,
    })


class Reader:
    rows = []

    def __init__(self):
        self.queries = []

    def list_active(self, query):
        self.queries.append(query)
        rows = [row for row in self.rows if query.after is None or (row.observed_at, row.id) < query.after]
        return rows[:query.limit + 1]


@pytest.fixture
def api():
    reader = Reader()
    previous = app.dependency_overrides.copy()

    def forbidden():
        raise AssertionError("The public observation station must not request private authentication")

    app.dependency_overrides[get_current_identity] = forbidden
    app.dependency_overrides[get_admin_web_session] = forbidden
    app.dependency_overrides[get_public_observation_reader] = lambda: reader
    yield TestClient(app), reader
    app.dependency_overrides.clear()
    app.dependency_overrides.update(previous)


def test_public_observations_have_explicit_field_allowlist(api):
    client, reader = api
    row = observation(description="Baleine", author_username="Léa")
    # Even a future repository accidentally returning internal properties must
    # not widen the public API response.
    reader.rows = [SimpleNamespace(**vars(row), author_id=UUID(int=99),
                                   author_email="private@nowave.test", boat_name="Private boat",
                                   photo_object_key="hidden-photo.jpg", removed_at=None)]
    response = client.get("/api/v1/map/observations")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert "set-cookie" not in response.headers
    item = response.json()["items"][0]
    assert set(item) == {
        "id", "category", "longitude", "latitude", "observed_at", "expires_at",
        "description", "author_username",
    }
    assert item["author_username"] == "Léa"
    assert response.json()["has_more"] is False


def test_inactive_optional_fields_are_absent(api):
    client, reader = api
    reader.rows = [observation()]
    item = client.get("/api/v1/map/observations").json()["items"][0]
    assert "author_username" not in item
    assert "description" not in item


def test_bounded_cursor_pagination_keeps_all_results_without_duplicates(api):
    client, reader = api
    reader.rows = [observation(1), observation(2), observation(3)]
    first = client.get("/api/v1/map/observations", params={"limit": 2}).json()
    assert len(first["items"]) == 2
    assert first["has_more"] is True
    second = client.get("/api/v1/map/observations", params={"limit": 2, "cursor": first["next_cursor"]}).json()
    assert [item["id"] for item in second["items"]] == [str(UUID(int=3))]
    assert second["has_more"] is False


def test_wrapped_bounds_and_filters_are_passed_without_reversing_dateline(api):
    client, reader = api
    response = client.get("/api/v1/map/observations", params={
        "west": 170, "east": -170, "south": -30, "north": 0,
        "category": "pollution", "q": "  plastique  ", "limit": 12,
    })
    assert response.status_code == 200
    query = reader.queries[-1]
    assert (query.west, query.east, query.south, query.north) == (170, -170, -30, 0)
    assert query.category == ReportCategory.POLLUTION
    assert query.q == "plastique"
    assert query.limit == 12


@pytest.mark.parametrize("params", [
    {"limit": 0}, {"limit": 501}, {"limit": "nan"}, {"q": "x" * 121},
    {"category": "removed"}, {"west": 170},
    {"west": 0, "east": 0, "south": 0, "north": 20},
    {"west": -180, "east": 180, "south": 20, "north": 0},
    {"west": -181, "east": 180, "south": 0, "north": 20},
    {"west": "nan", "east": 180, "south": 0, "north": 20},
    {"west": -180, "east": 180, "south": 0, "north": "inf"},
    {"cursor": "not-a-cursor"}, {"cursor": ""}, {"cursor": "x" * 161},
])
def test_invalid_query_is_rejected_before_repository_access(api, params):
    client, reader = api
    assert client.get("/api/v1/map/observations", params=params).status_code == 422
    assert reader.queries == []


def test_public_route_does_not_open_existing_private_api():
    client = TestClient(app)
    assert client.get("/api/v1/reports/00000000-0000-0000-0000-000000000001").status_code == 401
    assert client.get("/api/v1/map/tiles/0/0/0.mvt").status_code == 401
