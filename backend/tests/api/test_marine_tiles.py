import mapbox_vector_tile
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.application.services.marine_tiles import MarineTileResult
from app.domain.marine import ProviderUnavailable


@pytest.mark.parametrize(
    "family,layer",
    [
        ("seamarks", "seamark"),
        ("port-infrastructure", "pier_lines"),
        ("harbours", "harbour"),
        ("depth-contours", "depth_contour"),
        ("soundings", "sounding"),
        ("underwater-hazards", "underwater_hazard"),
    ],
)
def test_public_marine_endpoints_return_valid_mvt_and_degradation_metadata(
    monkeypatch, family, layer
):
    seen = []

    class Service:
        async def get_tile(self, tile, kind):
            seen.append((tile, kind))
            return MarineTileResult(
                mapbox_vector_tile.encode({"name": layer, "features": []}),
                ("shom:deadline",),
                ("osm",),
            )

    monkeypatch.setattr(
        "app.api.routes.map_tiles.get_marine_service", lambda: Service()
    )
    response = TestClient(app).get(f"/api/v1/map/{family}/12/2115/1503.pbf")
    assert response.status_code == 200
    assert layer in mapbox_vector_tile.decode(response.content)
    assert response.headers["content-type"] == "application/vnd.mapbox-vector-tile"
    assert response.headers["cache-control"] == (
        "no-store" if family == "soundings" else "public, max-age=15"
    )
    assert response.headers["x-nowave-marine-status"] == "degraded"
    assert response.headers["x-nowave-marine-sources"] == "osm"
    assert seen[0][0].x == 2115


@pytest.mark.parametrize(
    "path",
    [
        "seamarks/2/4/0",
        "port-infrastructure/2/0/4",
        "harbours/6/64/0",
        "harbours/15/0/0",
        "seamarks/15/0/0",
        "seamarks/-1/0/0",
    ],
)
def test_invalid_tiles_rejected_before_provider_access(path):
    assert TestClient(app).get(f"/api/v1/map/{path}.pbf").status_code == 422


def test_total_outage_is_503_not_cached_empty_tile(monkeypatch):
    class Service:
        async def get_tile(self, *args):
            raise ProviderUnavailable("all down")

    monkeypatch.setattr(
        "app.api.routes.map_tiles.get_marine_service", lambda: Service()
    )
    response = TestClient(app).get("/api/v1/map/seamarks/12/2115/1503.pbf")
    assert response.status_code == 503
    assert "cache-control" not in response.headers


def test_source_licenses_are_public_and_include_every_integrated_dataset():
    response = TestClient(app).get("/api/v1/map/marine-sources")
    data = response.json()
    assert "not for navigation" in data["usage"]
    assert {s["id"] for s in data["sources"]} == {
        "shom",
        "noaa",
        "osm",
        "openwaters",
        "openwaters-harbours",
        "ign",
        "shom-hazards",
        "shom-surveys",
        "emodnet-contours",
        "emodnet-dtm-2024",
        "osm-coastline-mask",
    }
    assert all(s["license_url"] and s["attribution"] for s in data["sources"])
