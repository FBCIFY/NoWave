"""Verify upstream restraint separately from the local reverse-proxy budget."""

import asyncio
from datetime import datetime, timezone
from email.utils import format_datetime
import os
from pathlib import Path
import shutil

import httpx
import pytest

from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.http import MarineHTTP


@pytest.mark.parametrize("status", [429, 503])
@pytest.mark.parametrize("header", ["45", "date", "invalid"])
def test_retry_after_blocks_network_until_deadline_and_does_not_cache_errors(
    tmp_path, monkeypatch, status, header
):
    now = [1_000_000.0]
    monkeypatch.setattr("app.infrastructure.marine.http.time.time", lambda: now[0])
    value = (format_datetime(datetime.fromtimestamp(now[0] + 45, timezone.utc), usegmt=True)
             if header == "date" else header)
    delay = 30 if header == "invalid" else 45
    calls = []

    async def run():
        def upstream(request):
            calls.append(str(request.url))
            return (httpx.Response(status, headers={"Retry-After": value})
                    if len(calls) == 1 else httpx.Response(200, content=b"recovered"))

        client = MarineHTTP(tmp_path / "cache.sqlite3", httpx.MockTransport(upstream))
        try:
            with pytest.raises(ProviderUnavailable):
                await client.get("https://provider.test/a")
            assert client._db().execute("SELECT count(*) FROM responses").fetchone() == (0,)
            now[0] += delay - 1
            with pytest.raises(ProviderUnavailable):
                await client.get("https://provider.test/b")
            assert len(calls) == 1
            now[0] += 2
            assert await client.get("https://provider.test/b") == b"recovered"
            assert len(calls) == 2
        finally:
            await client.close()

    asyncio.run(run())


def test_identical_concurrent_tiles_make_one_provider_request(tmp_path):
    calls = []

    async def upstream(request):
        calls.append(str(request.url))
        await asyncio.sleep(.02)
        return httpx.Response(200, content=b"shared")

    async def run():
        client = MarineHTTP(tmp_path / "cache.sqlite3", httpx.MockTransport(upstream))
        try:
            values = await asyncio.gather(*[
                client.get("https://provider.test/tile", osm=True) for _ in range(12)
            ])
            assert values == [b"shared"] * 12
            assert client.metrics == {"network_requests": 1, "cache_hits": 11}
        finally:
            await client.close()

    asyncio.run(run())
    assert len(calls) == 1


def test_actual_nginx_navigation_with_warm_cache_and_protected_general_api():
    nginx = os.environ.get("NOWAVE_TEST_NGINX") or shutil.which("nginx")
    if not nginx:
        pytest.skip("Set NOWAVE_TEST_NGINX to execute the local native Nginx probe")
    from tools.probe_marine_rate_limits import probe

    root = Path(__file__).resolve().parents[3]
    result = probe(nginx, root / "deploy/web/nginx.conf")
    snapshots = next(c for c in result["cases"] if c["scenario"] == "geojson_viewport")
    assert snapshots["requests"] == 45
    for case in result["cases"]:
        assert case["statuses"] == {200: case["requests"]}, case
        assert case["profile_status"] == 200, case
    assert result["warm_cache_provider_requests"] == 0
    assert result["warm_cache_hits"] == sum(c["requests"] for c in result["cases"])
    assert result["refresh"] == {"statuses": {200: 7}, "provider_requests": 7}
    assert result["general_api_abuse_statuses"][429] > 0
    assert result["proxy_rate_rejections"] > 0
    assert result["upstream_429"] == 0
