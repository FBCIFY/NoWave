"""Route -> service -> real provider -> durable cache, without public traffic."""

import json
from pathlib import Path

from fastapi.testclient import TestClient
import httpx
import mapbox_vector_tile

from app.application.services.marine_tiles import MarineTileService
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.providers import ShomProvider
from app.main import app


def test_provider_route_recovers_with_writable_cache_and_reuses_it(tmp_path, monkeypatch):
    fixture = json.loads((Path(__file__).parents[1] / "fixtures/marine/shom.json").read_text())
    volume = tmp_path / "volume"
    volume.mkdir()
    # A file occupying the directory is an actual OS write failure, even as root.
    forbidden = tmp_path / "not-a-directory"
    forbidden.write_bytes(b"must-not-change")
    calls = []

    def upstream(request):
        code = request.url.params["typeName"].split(":")[1]
        calls.append(code)
        return httpx.Response(200, json={
            "type": "FeatureCollection", "features": fixture.get(code, []),
        })

    def request(directory):
        monkeypatch.setenv("MARINE_CACHE_DIR", str(directory))
        http = MarineHTTP(transport=httpx.MockTransport(upstream))
        service = MarineTileService([ShomProvider(http)])
        monkeypatch.setattr("app.api.routes.map_tiles.get_marine_service", lambda: service)
        with TestClient(app) as client:
            try:
                result = client.get("/api/v1/map/seamarks/12/2115/1503.pbf")
                metrics = dict(http.metrics)
            finally:
                client.portal.call(http.close)
        return result, metrics

    failed, _ = request(forbidden / "cache")
    assert failed.status_code == 503
    assert calls == []
    assert forbidden.read_bytes() == b"must-not-change"

    first, first_metrics = request(volume)
    assert first.status_code == 200
    assert mapbox_vector_tile.decode(first.content)["seamark"]["features"]
    assert first_metrics["network_requests"] > 0
    network_calls = len(calls)

    second, second_metrics = request(volume)
    assert second.status_code == 200
    assert second.content == first.content
    assert second_metrics["network_requests"] == 0
    assert second_metrics["cache_hits"] > 0
    assert len(calls) == network_calls
