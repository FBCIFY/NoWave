"""Exercise the production audit gate with Docker failures injected at its boundary."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


REVISION = "a" * 40
MIRROR = "mirror.gcr.io/aquasec/trivy-db:2"
FALLBACK = "ghcr.io/aquasecurity/trivy-db:2"
SOURCE = Path(__file__).resolve().parents[3] / "deploy/hostinger/build-and-audit.sh"


@pytest.fixture
def run_audit(tmp_path):
    script = tmp_path / "deploy/hostinger/build-and-audit.sh"
    script.parent.mkdir(parents=True)
    shutil.copyfile(SOURCE, script)
    (tmp_path / "deploy/tunnel").mkdir()
    marker = tmp_path / "test-results/production-audit-ok"
    marker.parent.mkdir()
    # A failed rerun must invalidate even a previous success for the same SHA.
    marker.write_text(REVISION + "\n")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    docker = bin_dir / "docker"
    docker.write_text(
        f"#!{sys.executable}\n"
        """
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ['DOCKER_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if '--download-db-only' in args:
    repository = args[args.index('--db-repository') + 1]
    if os.environ['DB_FAILURE'] == 'all' or (
        os.environ['DB_FAILURE'] == 'mirror' and repository.startswith('mirror.gcr.io/')
    ):
        print('failed to fetch the layer: 404 Not Found', file=sys.stderr)
        sys.exit(1)
elif '--input' in args:
    sys.exit(int(os.environ['SCAN_EXIT']))
elif 'config' in args:
    sys.exit(int(os.environ['CONFIG_EXIT']))
"""
    )
    docker.chmod(0o755)
    log = tmp_path / "docker.jsonl"

    def run(db_failure="none", scan_exit=0, config_exit=0):
        result = subprocess.run(
            ["bash", str(script), REVISION],
            env={
                **os.environ,
                "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                "DOCKER_LOG": str(log),
                "DB_FAILURE": db_failure,
                "SCAN_EXIT": str(scan_exit),
                "CONFIG_EXIT": str(config_exit),
            },
            capture_output=True,
            text=True,
            timeout=30,
        )
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        return result, calls, marker

    return run


@pytest.mark.parametrize(
    ("db_failure", "expected_sources"),
    [("none", [MIRROR]), ("mirror", [MIRROR, FALLBACK])],
)
def test_database_download_then_all_mandatory_audits(run_audit, db_failure, expected_sources):
    result, calls, marker = run_audit(db_failure=db_failure)
    assert result.returncode == 0, result.stderr
    downloads = [call for call in calls if "--download-db-only" in call]
    assert [call[call.index("--db-repository") + 1] for call in downloads] == expected_sources
    assert calls[: len(downloads)] == downloads
    scans = [call for call in calls if "--input" in call]
    assert [call[call.index("--input") + 1] for call in scans] == [
        f"/scan/{component}.tar" for component in ("api", "web", "postgres", "tunnel")
    ]
    for call in downloads + scans:
        assert call[call.index("--cache-dir") + 1] == "/scan/cache"
        assert call[call.index("-v") + 1] == f"{marker.parent}/containers:/scan"
    for call in scans:
        assert "--skip-db-update" in call
        assert call[call.index("--exit-code") + 1] == "1"
        assert call[call.index("--severity") + 1] == "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
    assert "--vex" in scans[-1]
    assert "config" in calls[-1]
    assert calls[-1][calls[-1].index("--exit-code") + 1] == "1"
    assert marker.read_text() == REVISION + "\n"


def test_all_database_sources_failing_blocks_build_and_removes_old_evidence(run_audit):
    result, calls, marker = run_audit(db_failure="all")
    assert result.returncode != 0
    assert len(calls) == 2
    assert all("--download-db-only" in call for call in calls)
    assert "No Trivy database source succeeded" in result.stderr
    assert not marker.exists()


@pytest.mark.parametrize("scan_exit", [1, 2])
def test_vulnerabilities_or_scanner_errors_after_fallback_block_release(run_audit, scan_exit):
    result, calls, marker = run_audit(db_failure="mirror", scan_exit=scan_exit)
    assert result.returncode == scan_exit
    assert len([call for call in calls if "--download-db-only" in call]) == 2
    assert len([call for call in calls if "--input" in call]) == 1
    assert "--input" in calls[-1]
    assert not marker.exists()


def test_configuration_audit_failure_blocks_release(run_audit):
    result, calls, marker = run_audit(config_exit=1)
    assert result.returncode == 1
    assert len([call for call in calls if "--input" in call]) == 4
    assert "config" in calls[-1]
    assert not marker.exists()
