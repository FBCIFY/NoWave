"""Run the real deployment shell scripts in a private filesystem with injected I/O.

Docker, curl and systemd are simulated; Bash, file copies, unique directories,
atomic renames and advisory locks are real. Linux CI uses util-linux flock;
macOS uses the same OS flock primitive through a small CLI compatibility shim.
"""

import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

import pytest


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = Path(os.environ.get("NOWAVE_SCRIPT_TEST_SOURCE", ROOT / "deploy/hostinger"))
OLD = "a" * 40
NEW = "b" * 40


BOUNDARY = r'''
import json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['TEST_ROOT'])
state_path = root / 'state.json'
state = json.loads(state_path.read_text())
revision = None
if '--env-file' in args:
    env_file = pathlib.Path(args[args.index('--env-file') + 1])
    if env_file.exists():
        revision = env_file.read_text().strip().split('=', 1)[1]
marker = root / 'current-revision'
event = {'command': name, 'args': args, 'revision': revision,
         'marker': marker.read_text().strip() if marker.exists() else None}
with (root / 'events.jsonl').open('a') as log:
    log.write(json.dumps(event) + '\n')
failure = os.environ.get('FAILURE', '')
old, new = os.environ['OLD'], os.environ['NEW']

def save():
    state_path.write_text(json.dumps(state))

if name == 'docker':
    if args[:2] == ['image', 'inspect']:
        print(new)
    elif args[0] == 'inspect':
        actual = state['services'].get('notifications')
        if failure == 'worker_revision' and actual == new:
            actual = old
        print(json.dumps([{'State': {'Running': True}, 'Config': {
            'Cmd': ['python', '-m', 'app.workers.notifications'],
            'Labels': {'org.opencontainers.image.revision': actual}}}]))
    elif 'pg_dump' in args:
        run = os.environ.get('RUN_ID', 'single')
        (root / ('dump-entered-' + run)).touch()
        if os.environ.get('PAUSE_DUMP'):
            deadline = time.monotonic() + 8
            while not (root / 'dump-release').exists():
                if time.monotonic() > deadline:
                    sys.exit(80)
                time.sleep(0.01)
        print('dump-' + run)
        if failure == 'dump': sys.exit(21)
    elif 'pg_restore' in args:
        data = sys.stdin.read()
        if failure == 'restore' or not data.startswith('dump-'): sys.exit(22)
    elif 'logs' in args:
        print('synthetic service logs')
        if failure == 'logs': sys.exit(23)
    elif 'ps' in args:
        if failure == 'tunnel_state': sys.exit(46)
        service = args[-1]
        if service in state['services']: print('test-' + service)
    elif 'config' in args:
        if os.environ.get('FAIL_ROLLBACK_CONFIG') and revision == old: sys.exit(47)
        print('api\nweb\nnotifications\nphoto-cleanup\ndatabase')
    elif 'run' in args and 'migrate' in args:
        if failure == 'migration': sys.exit(41)
    elif 'stop' in args:
        for service in args[args.index('stop') + 1:]:
            state['services'].pop(service, None)
        save()
    elif 'up' in args:
        services = [s for s in args[args.index('up') + 1:]
                    if s in ('api', 'web', 'database', 'notifications', 'photo-cleanup', 'tunnel')]
        if os.environ.get('FAIL_ROLLBACK') and revision == old: sys.exit(44)
        for service in services: state['services'][service] = revision
        save()
        if failure == 'tunnel' and revision == new and 'tunnel' in services: sys.exit(42)
    else:
        raise AssertionError(args)
elif name == 'curl':
    url = next(a for a in args if a.startswith('http'))
    public = url.startswith('https:')
    active = state['services'].get('api')
    if public:
        if os.environ.get('PAUSE_PUBLIC') and active == new:
            (root / 'public-entered').touch()
            deadline = time.monotonic() + 8
            while not (root / 'public-release').exists():
                if time.monotonic() > deadline: sys.exit(81)
                time.sleep(0.01)
        state['public_calls'] = state.get('public_calls', 0) + 1
        save()
        if failure == 'public_unavailable': sys.exit(22)
        if active == new and (failure == 'public_http' or
                             (failure == 'public_retry' and state['public_calls'] <= 2)):
            sys.exit(22)
        if active == new and os.environ.get('FAIL_MARINE_TILE') and (
            url.endswith('/api/v1/map/' + os.environ['FAIL_MARINE_TILE'])
        ):
            sys.exit(22)
    elif active == new and failure == 'private_http':
        sys.exit(22)
    if 'Host: untrusted.example' in args:
        print('421', end='')
    elif 'Origin: https://untrusted.example' in args:
        print('403', end='')
    elif url.endswith('/api/v1/users/me'):
        print('401', end='')
    elif url.endswith('/version.json') or url.endswith('/version'):
        value = old if public and active == new and failure == 'public_version' else active
        print(json.dumps({'version': value}))
    elif url.endswith('/health/ready'):
        value = 'bad' if public and active == new and failure == 'public_ready' else 'ok'
        print(json.dumps({'database': value}))
    else:
        print('synthetic asset')
elif name == 'systemctl':
    if failure == 'timer': sys.exit(45)
elif name not in ('chown', 'sleep'):
    raise AssertionError(name)
'''


class Sandbox:
    def __init__(self, path):
        self.root = path / "vps"
        self.source = path / "source"
        self.bin = path / "bin"
        for directory in (self.root / "config", self.root / "secrets",
                          self.root / "backups", self.root / "systemd", self.bin,
                          self.source / "deploy/hostinger", self.source / "test-results"):
            directory.mkdir(parents=True, exist_ok=True)
        self.env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                    "TEST_ROOT": str(self.root), "OLD": OLD, "NEW": NEW}
        self.processes = []
        for file in SCRIPTS.glob("*.sh"):
            text = file.read_text().replace("/opt/nowave", str(self.root))
            text = text.replace("/etc/systemd/system", str(self.root / "systemd"))
            text = text.replace("[[ $EUID == 0 ]]", "[[ 1 == 1 ]]")
            # ci-deploy normally finds the transferred archive by SHA.
            text = text.replace('source_root="' + str(self.root) + '/releases/$revision"',
                                'source_root="' + str(self.source) + '"')
            (self.source / "deploy/hostinger" / file.name).write_text(text)
        (self.source / "deploy/hostinger/bootstrap.py").write_text("# No host provisioning in tests.\n")
        for name in ("nowave-backup.service", "nowave-backup.timer",
                     "nowave-build-cache.service", "nowave-build-cache.timer"):
            shutil.copyfile(ROOT / "deploy/hostinger" / name, self.source / "deploy/hostinger" / name)
        (self.source / "deploy/compose.yaml").write_text("new-compose\n")
        (self.source / "deploy/tunnel.yaml").write_text("new-tunnel\n")
        (self.source / "test-results/production-audit-ok").write_text(NEW + "\n")
        for name in ("docker", "curl", "systemctl", "chown", "sleep"):
            self.executable(name, f"#!{sys.executable}\n" + BOUNDARY)
        self.executable("date", "#!/bin/sh\nprintf '20261020T120000Z\\n'\n")
        if shutil.which("flock") is None:
            self.executable("flock", f"#!{sys.executable}\nimport fcntl, sys\n"
                            "try: fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
                            "except BlockingIOError: sys.exit(1)\n")
        for name in ("firebase_web_api_key", "tunnel_token", "scaleway_access_key", "scaleway_secret_key"):
            (self.root / "secrets" / name).write_text("synthetic-test-only\n")
        (self.root / "secrets/firebase_service_account.json").write_text(json.dumps(
            {"type": "service_account", "project_id": "blueway-dev", "private_key": "synthetic"}))
        (self.root / "config/photo-storage.env").write_text("test-only\n")
        self.seed()

    def executable(self, name, text):
        file = self.bin / name
        file.write_text(text)
        file.chmod(0o755)

    def seed(self, *, previous=True, tunnel=True, running=True):
        services = {}
        config = self.root / "config"
        for name in ("release.env", "compose.yaml", "tunnel.yaml"):
            (config / name).unlink(missing_ok=True)
        (self.root / "current-revision").unlink(missing_ok=True)
        if previous:
            (config / "release.env").write_text(f"NOWAVE_VERSION={OLD}\n")
            (config / "compose.yaml").write_text("old-compose\n")
            (self.root / "current-revision").write_text(OLD + "\n")
            services = dict.fromkeys(("api", "web", "database", "notifications", "photo-cleanup"), OLD)
            if tunnel:
                (config / "tunnel.yaml").write_text("old-tunnel\n")
                if running: services["tunnel"] = OLD
        (self.root / "state.json").write_text(json.dumps({"services": services}))

    def start(self, script, **env):
        args = ["bash", str(self.source / "deploy/hostinger" / script)]
        if script != "backup.sh": args.append(NEW)
        process = subprocess.Popen(args, env={**self.env, **env}, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.processes.append(process)
        return process

    def run(self, script="deploy.sh", **env):
        process = self.start(script, **env)
        stdout, stderr = process.communicate(timeout=20)
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def events(self):
        file = self.root / "events.jsonl"
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def services(self):
        return json.loads((self.root / "state.json").read_text())["services"]

    def assert_restored(self, *, tunnel=True, running=True):
        assert (self.root / "config/release.env").read_text() == f"NOWAVE_VERSION={OLD}\n"
        assert (self.root / "config/compose.yaml").read_text() == "old-compose\n"
        assert (self.root / "current-revision").read_text().strip() == OLD
        assert not (self.root / "current-revision.tmp").exists()
        services = self.services()
        for name in ("api", "web", "notifications", "photo-cleanup"):
            assert services[name] == OLD
        if tunnel:
            assert (self.root / "config/tunnel.yaml").read_text() == "old-tunnel\n"
            if running: assert services["tunnel"] == OLD
            else: assert "tunnel" not in services
        else:
            assert not (self.root / "config/tunnel.yaml").exists()
            assert "tunnel" not in services


@pytest.fixture
def sandbox(tmp_path):
    box = Sandbox(tmp_path)
    yield box
    for process in box.processes:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)


def wait_for(file):
    deadline = time.monotonic() + 5
    while not file.exists():
        assert time.monotonic() < deadline, f"Timed out waiting for {file}"
        time.sleep(0.01)


def test_untrusted_host_simulation_returns_expected_http_status(sandbox):
    # Check the boundary directly: Bash 3.2 does not apply errexit to a failing
    # [[ ... ]] the same way as Linux Bash, and can otherwise hide a bad mock.
    result = subprocess.run(
        [str(sandbox.bin / "curl"), "-s", "-o", "/dev/null", "-w", "%{http_code}",
         "-H", "Host: untrusted.example", "http://127.0.0.1:18080/"],
        env=sandbox.env, capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "421"


def test_concurrent_backups_same_second_have_separate_unpublished_dumps(sandbox):
    processes = [sandbox.start("backup.sh", RUN_ID=name, PAUSE_DUMP="1") for name in ("one", "two")]
    for name in ("one", "two"): wait_for(sandbox.root / ("dump-entered-" + name))
    backups = sandbox.root / "backups"
    assert not list(backups.glob("*/database.dump")), "A partial dump was published"
    assert len(list(backups.iterdir())) == 2, "Concurrent writers share a directory"
    (sandbox.root / "dump-release").touch()
    for process in processes:
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 0, stderr
        assert "Private backup created:" in stdout
    dumps = list(backups.glob("*/database.dump"))
    assert {file.read_text().strip() for file in dumps} == {"dump-one", "dump-two"}
    assert not list(backups.glob("*/*.partial"))
    for file in dumps:
        assert file.stat().st_mode & 0o077 == 0
        assert file.parent.stat().st_mode & 0o077 == 0
        assert (file.parent / "release.env").exists()
        assert (file.parent / "services.log").exists()


def test_sequential_backups_same_second_do_not_overwrite(sandbox):
    for name in ("one", "two"):
        result = sandbox.run("backup.sh", RUN_ID=name)
        assert result.returncode == 0, result.stderr
    assert {p.read_text().strip() for p in (sandbox.root / "backups").glob("*/database.dump")} == {
        "dump-one", "dump-two"}


@pytest.mark.parametrize("failure", ["dump", "restore", "logs"])
def test_backup_failure_removes_partial_output_and_keeps_prior_backup(sandbox, failure):
    previous = sandbox.run("backup.sh", RUN_ID="previous")
    assert previous.returncode == 0, previous.stderr
    result = sandbox.run("backup.sh", FAILURE=failure)
    assert result.returncode != 0
    assert "Private backup created:" not in result.stdout
    directories = list((sandbox.root / "backups").iterdir())
    assert len(directories) == 1
    assert (directories[0] / "database.dump").read_text().strip() == "dump-previous"


def test_backup_copy_failure_cleans_partial_output(sandbox):
    (sandbox.root / "config/compose.yaml").unlink()
    result = sandbox.run("backup.sh")
    assert result.returncode != 0
    assert not list((sandbox.root / "backups").iterdir())


def test_backup_termination_cleans_partial_output(sandbox):
    process = sandbox.start("backup.sh", PAUSE_DUMP="1")
    wait_for(sandbox.root / "dump-entered-single")
    os.killpg(process.pid, signal.SIGTERM)
    process.communicate(timeout=10)
    assert process.returncode != 0
    assert not list((sandbox.root / "backups").iterdir())


def test_backup_without_release_is_a_noop(sandbox):
    sandbox.seed(previous=False)
    result = sandbox.run("backup.sh")
    assert result.returncode == 0
    assert not list((sandbox.root / "backups").iterdir())


@pytest.mark.parametrize("failure", ["migration", "private_http", "worker_revision", "tunnel",
                                     "public_http", "public_version", "public_ready", "timer"])
def test_deployment_failure_restores_previous_release_and_tunnel(sandbox, failure):
    result = sandbox.run(FAILURE=failure)
    assert result.returncode != 0, result.stdout
    assert "live and healthy" not in result.stdout
    assert "Rollback incomplete" not in result.stderr
    sandbox.assert_restored()
    assert list((sandbox.root / "backups").glob("*/database.dump"))


@pytest.mark.parametrize("previous", [True, False])
def test_success_commits_revision_only_after_public_validation(sandbox, previous):
    sandbox.seed(previous=previous)
    result = sandbox.run()
    assert result.returncode == 0, result.stderr
    assert (sandbox.root / "current-revision").read_text().strip() == NEW
    assert all(value == NEW for value in sandbox.services().values())
    public = [e for e in sandbox.events() if e["command"] == "curl" and any(
        a.startswith("https:") for a in e["args"])]
    # Three version/health requests and four representative marine tiles.
    # They must all finish before the new revision marker is published.
    assert len(public) == 7
    urls = {a for e in public for a in e["args"] if a.startswith("https:")}
    assert urls == {
        "https://no-wave.fr/version.json",
        "https://api.no-wave.fr/version",
        "https://api.no-wave.fr/health/ready",
        "https://api.no-wave.fr/api/v1/map/seamarks/12/2115/1503.pbf",
        "https://api.no-wave.fr/api/v1/map/soundings/12/2115/1503.pbf",
        "https://api.no-wave.fr/api/v1/map/bathymetry/12/2115/1503.png",
        "https://api.no-wave.fr/api/v1/map/seafloor/gebco-2026-v2/6/57/25.webp",
    }
    assert all(e["marker"] == (OLD if previous else None) for e in public)


def test_transient_public_failure_retries_before_committing(sandbox):
    result = sandbox.run(FAILURE="public_retry")
    assert result.returncode == 0, result.stderr
    # Two transient failures then three version/health and four marine calls.
    assert json.loads((sandbox.root / "state.json").read_text())["public_calls"] == 9
    assert (sandbox.root / "current-revision").read_text().strip() == NEW


@pytest.mark.parametrize("tile", [
    "seamarks/12/2115/1503.pbf",
    "soundings/12/2115/1503.pbf",
    "bathymetry/12/2115/1503.png",
    "seafloor/gebco-2026-v2/6/57/25.webp",
])
def test_marine_public_failure_rolls_back_before_publishing_revision(sandbox, tile):
    result = sandbox.run(FAIL_MARINE_TILE=tile)
    assert result.returncode != 0
    assert f"Marine public smoke check failed for {tile}" in result.stderr
    assert "live and healthy" not in result.stdout
    assert "Rollback incomplete" not in result.stderr
    sandbox.assert_restored()


@pytest.mark.parametrize("tunnel,running", [(False, False), (True, False)])
def test_rollback_preserves_absent_or_stopped_previous_tunnel(sandbox, tunnel, running):
    sandbox.seed(tunnel=tunnel, running=running)
    result = sandbox.run(FAILURE="public_http")
    assert result.returncode != 0
    sandbox.assert_restored(tunnel=tunnel, running=running)


def test_first_deployment_failure_does_not_reuse_stale_rollback_files(sandbox):
    sandbox.seed(previous=False)
    (sandbox.root / "config/release.rollback.env").write_text(f"NOWAVE_VERSION={OLD}\n")
    (sandbox.root / "config/compose.rollback.yaml").write_text("stale-compose\n")
    result = sandbox.run(FAILURE="public_http")
    assert result.returncode != 0
    assert not (sandbox.root / "current-revision").exists()
    assert not (sandbox.root / "config/release.env").exists()
    assert not (sandbox.root / "config/tunnel.yaml").exists()
    assert sandbox.services() == {"database": NEW}


def test_missing_tunnel_token_blocks_activation(sandbox):
    (sandbox.root / "secrets/tunnel_token").unlink()
    result = sandbox.run()
    assert result.returncode != 0
    sandbox.assert_restored()
    assert not any("up" in e["args"] for e in sandbox.events())


def test_unknown_previous_tunnel_state_blocks_activation(sandbox):
    result = sandbox.run(FAILURE="tunnel_state")
    assert result.returncode != 0
    sandbox.assert_restored()
    assert not any("up" in e["args"] for e in sandbox.events())


def test_failed_rollback_configuration_is_reported(sandbox):
    result = sandbox.run(FAILURE="public_http", FAIL_ROLLBACK_CONFIG="1")
    assert result.returncode != 0
    assert "Rollback incomplete; manual recovery is required." in result.stderr
    assert "live and healthy" not in result.stdout


def test_failed_rollback_is_reported_without_claiming_success(sandbox):
    result = sandbox.run(FAILURE="public_http", FAIL_ROLLBACK="1")
    assert result.returncode != 0
    assert "Rollback incomplete; manual recovery is required." in result.stderr
    assert "live and healthy" not in result.stdout
    assert (sandbox.root / "current-revision").read_text().strip() == OLD


def test_public_outage_after_rollback_is_reported(sandbox):
    result = sandbox.run(FAILURE="public_unavailable")
    assert result.returncode != 0
    assert "Rollback incomplete; manual recovery is required." in result.stderr
    sandbox.assert_restored()


def test_termination_during_public_validation_rolls_back(sandbox):
    process = sandbox.start("deploy.sh", PAUSE_PUBLIC="1")
    wait_for(sandbox.root / "public-entered")
    os.killpg(process.pid, signal.SIGTERM)
    process.communicate(timeout=10)
    assert process.returncode != 0
    sandbox.assert_restored()


def test_termination_just_after_marker_publication_restores_marker_too(sandbox):
    real_mv = shutil.which("mv")
    sandbox.executable("mv", f"#!{sys.executable}\n"
                       "import os, pathlib, signal, subprocess, sys\n"
                       f"result = subprocess.run([{real_mv!r}, *sys.argv[1:]])\n"
                       "destination = pathlib.Path(sys.argv[-1])\n"
                       "if destination.name == 'current-revision' and "
                       "destination.read_text().strip() == os.environ['NEW']:\n"
                       "    os.kill(os.getppid(), signal.SIGTERM)\n"
                       "sys.exit(result.returncode)\n")
    result = sandbox.run()
    assert result.returncode != 0
    sandbox.assert_restored()


def test_deployment_lock_blocks_a_second_deployment(sandbox):
    with (sandbox.root / "deploy.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = sandbox.run()
    assert result.returncode != 0
    assert "Another NoWave deployment is running" in result.stderr
    sandbox.assert_restored()


def test_ci_entrypoint_keeps_public_failure_inside_transaction(sandbox):
    (sandbox.source / "deploy/hostinger/build-and-audit.sh").write_text("exit 0\n")
    result = sandbox.run("ci-deploy.sh", FAILURE="public_http")
    assert result.returncode != 0
    sandbox.assert_restored()
