"""Exercise the durable cache used by every non-numeric marine provider."""

import asyncio
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys

import httpx
import pytest

from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.http import MarineHTTP


def test_configured_directory_wal_and_read_after_write(tmp_path, monkeypatch):
    directory = tmp_path / "volume"
    monkeypatch.setenv("MARINE_CACHE_DIR", str(directory))
    calls = []

    async def run():
        def upstream(request):
            calls.append(request.url.path)
            return httpx.Response(200, content=b"marine-data")

        client = MarineHTTP(transport=httpx.MockTransport(upstream))
        try:
            assert client.path == directory / "http.sqlite3"
            assert await client.get("https://provider.test/tile") == b"marine-data"
            assert await client.get("https://provider.test/tile") == b"marine-data"
            assert client._db().execute("PRAGMA journal_mode").fetchone() == ("wal",)
            assert client.path.with_name("http.sqlite3-wal").exists()
            assert client.path.with_name("http.sqlite3-shm").exists()
            assert client.metrics == {"cache_hits": 1, "network_requests": 1}
        finally:
            await client.close()

    asyncio.run(run())
    assert calls == ["/tile"]
    assert not (tmp_path / ".cache").exists()


def test_unwritable_cache_fails_before_network_without_bypass(tmp_path):
    directory = tmp_path / "denied"
    directory.mkdir()
    directory.chmod(0o500)
    if os.geteuid() == 0:
        directory.chmod(0o700)
        pytest.skip("Permission test requires an unprivileged user")
    calls = []

    async def run():
        client = MarineHTTP(
            directory / "marine/http.sqlite3",
            httpx.MockTransport(lambda request: calls.append(request)),
        )
        try:
            with pytest.raises(ProviderUnavailable) as caught:
                await client.get("https://provider.test/tile", osm=True)
            assert isinstance(caught.value.__cause__, PermissionError)
            assert client.metrics["network_requests"] == 0
        finally:
            await client.close()

    try:
        asyncio.run(run())
        assert not calls
        assert list(directory.iterdir()) == []
    finally:
        directory.chmod(0o700)


def test_sqlite_open_error_is_reported_as_provider_unavailable(tmp_path):
    path = tmp_path / "is-a-directory"
    path.mkdir()

    async def run():
        client = MarineHTTP(path)
        try:
            with pytest.raises(ProviderUnavailable) as caught:
                await client.get("https://provider.test/tile")
            assert isinstance(caught.value.__cause__, sqlite3.Error)
            assert client.metrics["network_requests"] == 0
        finally:
            await client.close()

    asyncio.run(run())


def test_cache_survives_a_new_process(tmp_path):
    script = """
import asyncio, json, httpx
from app.infrastructure.marine.http import MarineHTTP
async def run():
    client = MarineHTTP(transport=httpx.MockTransport(
        lambda request: httpx.Response(200, content=b'persisted')))
    try:
        assert await client.get('https://provider.test/tile', osm=True) == b'persisted'
        print(json.dumps(client.metrics))
    finally:
        await client.close()
asyncio.run(run())
"""
    root = Path(__file__).resolve().parents[3]
    env = {**os.environ, "MARINE_CACHE_DIR": str(tmp_path / "volume"),
           "PYTHONPATH": str(root / "backend")}

    def process():
        result = subprocess.run(
            [sys.executable, "-c", script], env=env, cwd=root,
            capture_output=True, text=True, check=True, timeout=20,
        )
        return json.loads(result.stdout)

    assert process() == {"cache_hits": 0, "network_requests": 1}
    assert process() == {"cache_hits": 1, "network_requests": 0}


@pytest.mark.parametrize("osm,max_age,expected_ttl", [
    (False, None, 10), (True, None, 604800), (True, "900000", 900000),
])
def test_ttl_expiry_and_osm_minimum(tmp_path, monkeypatch, osm, max_age, expected_ttl):
    now = [1_000_000.0]
    monkeypatch.setattr("app.infrastructure.marine.http.time.time", lambda: now[0])
    calls = []

    async def run():
        def upstream(request):
            calls.append(request.url.path)
            headers = {} if max_age is None else {"Cache-Control": f"max-age={max_age}"}
            return httpx.Response(200, content=b"tile", headers=headers)

        client = MarineHTTP(tmp_path / "cache.sqlite3", httpx.MockTransport(upstream))
        try:
            await client.get("https://provider.test/tile", ttl=10, osm=osm)
            expires = client._db().execute("SELECT expires FROM responses").fetchone()[0]
            assert expires == now[0] + expected_ttl
            now[0] += expected_ttl - 1
            await client.get("https://provider.test/tile", ttl=10, osm=osm)
            assert len(calls) == 1
            now[0] += 2
            await client.get("https://provider.test/tile", ttl=10, osm=osm)
            assert len(calls) == 2
        finally:
            await client.close()

    asyncio.run(run())


def test_compose_mounts_only_api_cache_and_retains_read_only(tmp_path):
    """Render the actual Compose file rather than testing YAML text snippets."""
    root = Path(__file__).resolve().parents[3]
    (tmp_path / "photo-storage.env").write_text("PHOTO_STORAGE_BUCKET=test-only\n")
    result = subprocess.run(
        ["docker", "compose", "-f", str(root / "deploy/compose.yaml"),
         "--profile", "api", "config", "--format", "json"],
        env={**os.environ, "NOWAVE_VERSION": "a" * 40,
             "NOWAVE_CONFIG_DIR": str(tmp_path), "NOWAVE_SECRETS_DIR": str(tmp_path)},
        capture_output=True, text=True, check=True, timeout=20,
    )
    config = json.loads(result.stdout)
    api = config["services"]["api"]
    assert api["read_only"] is True
    assert api["environment"]["MARINE_CACHE_DIR"] == "/var/cache/nowave/marine"
    mount, = api["volumes"]
    assert mount["type"] == "volume"
    assert mount["source"] == "marine-cache"
    assert mount["target"] == api["environment"]["MARINE_CACHE_DIR"]
    assert not mount.get("read_only", False)
    assert "marine-cache" in config["volumes"]
    assert config["services"]["database"]["volumes"][0]["source"] == "database"
    for name, service in config["services"].items():
        assert service["read_only"] is True, name
        if name != "api":
            assert all(v["source"] != "marine-cache" for v in service.get("volumes", []))
