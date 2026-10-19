"""Reject a successful release when its independent FCM worker is missing."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[3]
VERIFY = ROOT / "deploy/hostinger/verify-notifications.sh"
REVISION = "a" * 40


@pytest.fixture
def worker():
    return {
        "State": {"Running": True, "Restarting": False, "Paused": False},
        "Config": {
            "Cmd": ["python", "-m", "app.workers.notifications"],
            "Labels": {"org.opencontainers.image.revision": REVISION},
        },
    }


@pytest.fixture
def verify(tmp_path):
    docker = tmp_path / "docker"
    docker.write_text(
        f"#!{sys.executable}\n"
        "import os, sys\n"
        "assert sys.argv[1:] == ['inspect', 'worker-id']\n"
        "print(os.environ['INSPECT_RESULT'])\n"
        "sys.exit(int(os.environ['INSPECT_EXIT']))\n"
    )
    docker.chmod(0o755)

    def run(containers, *, inspect_exit=0, container="worker-id"):
        return subprocess.run(
            ["bash", str(VERIFY), REVISION, container],
            env={
                **os.environ,
                "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
                "INSPECT_RESULT": json.dumps(containers),
                "INSPECT_EXIT": str(inspect_exit),
            },
            capture_output=True,
            text=True,
            timeout=10,
        )

    return run


def test_running_worker_at_expected_revision_passes(verify, worker):
    result = verify([worker])
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("flag,value", [("Running", False), ("Restarting", True), ("Paused", True)])
def test_unavailable_worker_blocks_release(verify, worker, flag, value):
    worker["State"][flag] = value
    result = verify([worker])
    assert result.returncode != 0
    assert "not running" in result.stderr


def test_api_container_cannot_stand_in_for_worker(verify, worker):
    worker["Config"]["Cmd"] = ["uvicorn", "app.main:app"]
    result = verify([worker])
    assert result.returncode != 0
    assert "not running the FCM worker" in result.stderr


def test_previous_release_worker_cannot_validate_new_release(verify, worker):
    worker["Config"]["Labels"]["org.opencontainers.image.revision"] = "b" * 40
    result = verify([worker])
    assert result.returncode != 0
    assert "revision does not match" in result.stderr


def test_no_worker_blocks_release(verify):
    assert verify([]).returncode != 0
    assert verify([], container="").returncode != 0


def test_docker_failure_is_not_masked_by_valid_json(verify, worker):
    assert verify([worker], inspect_exit=1).returncode != 0


def test_production_api_profile_includes_fcm_worker(tmp_path):
    if shutil.which("docker") is None:
        pytest.skip("Docker Compose CLI is required to render deployment configuration")
    (tmp_path / "photo-storage.env").write_text("PHOTO_STORAGE_BUCKET=test-only\n")
    result = subprocess.run(
        ["docker", "compose", "-f", str(ROOT / "deploy/compose.yaml"),
         "--profile", "api", "config", "--format", "json"],
        env={**os.environ, "NOWAVE_VERSION": REVISION,
             "NOWAVE_CONFIG_DIR": str(tmp_path), "NOWAVE_SECRETS_DIR": str(tmp_path)},
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr
    services = json.loads(result.stdout)["services"]
    worker = services["notifications"]
    assert worker["image"] == services["api"]["image"]
    assert worker["command"] == ["python", "-m", "app.workers.notifications"]
    assert worker["restart"] == "unless-stopped"
    assert worker["healthcheck"]["disable"]  # No API HTTP probe in this process.
    assert set(worker["networks"]) == {"backend", "egress"}
    assert {secret["source"] for secret in worker["secrets"]} == {
        "database_url", "firebase_service_account",
    }
    assert worker["environment"]["DATABASE_URL_FILE"] == "/run/secrets/database_url"
    assert worker["environment"]["GOOGLE_APPLICATION_CREDENTIALS"] == "/run/secrets/firebase_service_account"
