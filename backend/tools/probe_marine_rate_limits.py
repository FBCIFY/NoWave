"""Bounded loopback-only Nginx/cache probe. Never contacts a public provider.

PYTHONPATH=backend python backend/tools/probe_marine_rate_limits.py \
  --nginx /path/to/nginx --config deploy/web/nginx.conf
"""

import argparse
import asyncio
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

import httpx

from app.infrastructure.marine.http import MarineHTTP


FAMILIES = ["bathymetry", "depth-contours", "soundings", "seamarks",
            "underwater-hazards", "port-infrastructure", "harbours"]
SNAPSHOT_FAMILIES = ["harbours", "seamarks", "depth-contours", "soundings",
                     "underwater-hazards"]


def tile_paths(offset, count, zoom=12):
    return [f"/api/v1/map/{family}/{zoom}/{2115 + offset + i}/1503."
            f"{'png' if family == 'bathymetry' else 'pbf'}"
            for i in range(count) for family in FAMILIES]


def snapshot_paths(count):
    return [f"/api/v1/map/marine-features/{family}/12/{2115 + i}/1503.geojson"
            for i in range(count) for family in SNAPSHOT_FAMILIES]


def probe(nginx, config):
    loop = asyncio.new_event_loop()
    thread = threading.Thread(target=loop.run_forever, daemon=True)
    thread.start()
    with tempfile.TemporaryDirectory(prefix="nowave-rate-probe-") as directory:
        root = Path(directory)
        cache = MarineHTTP(root / "cache/http.sqlite3", httpx.MockTransport(
            lambda request: httpx.Response(200, content=b"local-fixture")))

        async def get(path):
            return await cache.get("https://fixture.invalid" + path, ttl=300)

        viewport_paths = tile_paths(40, 9)
        overlapping_paths = tile_paths(60, 27)

        class Backend(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                data = (asyncio.run_coroutine_threadsafe(get(self.path), loop).result(10)
                        if self.path.startswith("/api/v1/map/") and self.path.endswith((".png", ".pbf", ".geojson"))
                        else b"{}")
                # One real viewport can request 9 tiles across 7 sources at
                # once. Keep those streams open to expose connection limits.
                if self.path in viewport_paths or self.path in overlapping_paths:
                    time.sleep(2)
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        class FixtureServer(ThreadingHTTPServer):
            request_queue_size = 128

        backend = FixtureServer(("127.0.0.1", 0), Backend)
        backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
        backend_thread.start()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        text = Path(config).read_text()
        text = text.replace("worker_processes auto;", "worker_processes 1;")
        text = text.replace("include /etc/nginx/mime.types;", "types { application/json json; }")
        text = text.replace("listen 8080", f"listen 127.0.0.1:{port}")
        text = text.replace("pid /tmp/nginx.pid;", f"pid {root}/nginx.pid;")
        text = text.replace("error_log /dev/stderr warn;", f"error_log {root}/error.log warn;")
        text = text.replace("access_log /dev/stdout safe_json;", f"access_log {root}/access.log safe_json;")
        text = text.replace("http://api:8000", f"http://127.0.0.1:{backend.server_port}")
        for name in ["client", "proxy", "fastcgi", "uwsgi", "scgi"]:
            text = text.replace(f"/tmp/{name};", f"{root}/{name};")
        rendered = root / "nginx.conf"
        rendered.write_text(text)
        process = None

        def request(path):
            req = urllib.request.Request(f"http://127.0.0.1:{port}" + path,
                                         headers={"Host": "api.no-wave.fr"})
            try:
                with urllib.request.urlopen(req, timeout=15) as result:
                    result.read()
                    return result.status
            except urllib.error.HTTPError as error:
                error.read()
                return error.code

        scenarios = [
            ("stable", tile_paths(0, 1)),
            ("horizontal", tile_paths(1, 2)),
            ("vertical", tile_paths(3, 2)),
            ("zoom_in", tile_paths(0, 4, 13)),
            ("zoom_out", tile_paths(0, 4, 11)),
            ("other_zone", tile_paths(20, 4)),
            ("revisit", tile_paths(0, 4)),
            ("geojson_viewport", snapshot_paths(9)),
            ("full_viewport", viewport_paths),
            ("repeat_viewport", viewport_paths),
            ("three_overlapping_viewports", overlapping_paths),
        ]
        # Warm the real durable cache before any proxy measurement, including
        # every navigation path. Nginx must not consume the profile budget even
        # when the providers receive no requests at all.
        async def warm():
            for path in {p for _, paths in scenarios for p in paths}:
                await get(path)

        asyncio.run_coroutine_threadsafe(warm(), loop).result(15)
        try:
            checked = subprocess.run([nginx, "-p", str(root), "-c", str(rendered), "-t"],
                                     capture_output=True, text=True, timeout=10)
            if checked.returncode:
                raise RuntimeError(checked.stderr)
            process = subprocess.Popen([nginx, "-p", str(root), "-c", str(rendered),
                                        "-g", "daemon off;"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            for _ in range(50):
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=.1):
                        break
                except OSError:
                    if process.poll() is not None:
                        raise RuntimeError(process.stderr.read().decode())
                    time.sleep(.05)
            before = dict(cache.metrics)
            cases = []
            for name, paths in scenarios:
                started = time.monotonic()
                with ThreadPoolExecutor(max_workers=192) as pool:
                    pending = [pool.submit(request, path) for path in paths]
                    # Profile requests must succeed while marine requests are
                    # still open, rather than only after the tiles complete.
                    time.sleep(.1)
                    profile = request("/api/v1/users/me")
                    codes = Counter(future.result() for future in pending)
                cases.append({"scenario": name, "requests": len(paths),
                              "statuses": dict(codes), "profile_status": profile,
                              "seconds": round(time.monotonic() - started, 3)})
                time.sleep(.25)
            after = dict(cache.metrics)
            # Refresh after expiry, only in the disposable synthetic cache.
            async def expire():
                cache._db().execute("UPDATE responses SET expires=0")
                cache._db().commit()
            asyncio.run_coroutine_threadsafe(expire(), loop).result(5)
            time.sleep(3.2)  # Drain even the original general API burst.
            refresh_before = cache.metrics["network_requests"]
            refresh = Counter(request(path) for path in tile_paths(0, 1))
            refresh_network = cache.metrics["network_requests"] - refresh_before
            # General API abuse protection must still reject a local burst.
            time.sleep(1)
            with ThreadPoolExecutor(max_workers=8) as pool:
                protected = Counter(pool.map(request, ["/api/v1/users/me"] * 55))
            process.terminate()
            process.wait(timeout=10)
            logs = [json.loads(line) for line in (root / "access.log").read_text().splitlines()]
            return {"cases": cases,
                    "warm_cache_provider_requests": after["network_requests"] - before["network_requests"],
                    "warm_cache_hits": after["cache_hits"] - before["cache_hits"],
                    "refresh": {"statuses": dict(refresh), "provider_requests": refresh_network},
                    "general_api_abuse_statuses": dict(protected),
                    "proxy_rate_rejections": sum(r["limit_req_status"] == "REJECTED" for r in logs),
                    "marine_connection_rejections": sum(
                        r["limit_conn_status"] == "REJECTED" and
                        any(f"/map/{family}/" in r["path"] for family in FAMILIES)
                        for r in logs),
                    "upstream_429": sum(r["upstream_status"] == "429" for r in logs),
                    "scope": "loopback nginx + real MarineHTTP cache + synthetic provider; no public traffic"}
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            backend.shutdown()
            backend.server_close()
            asyncio.run_coroutine_threadsafe(cache.close(), loop).result(5)
            loop.call_soon_threadsafe(loop.stop)
            thread.join(timeout=5)
            loop.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nginx", required=True)
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(probe(args.nginx, args.config), indent=2))
