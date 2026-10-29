#!/usr/bin/env bash
# A healthy API does not prove that the separate FCM consumer was started.
set -euo pipefail
expected=${1:?Expected revision required}
container=${2:?Notification container ID required}
docker inspect "$container" | python3 -c '
import json, sys

containers = json.load(sys.stdin)
if len(containers) != 1:
    raise SystemExit("Expected exactly one notification worker.")
container = containers[0]
state = container.get("State", {})
config = container.get("Config", {})
if not state.get("Running") or state.get("Restarting") or state.get("Paused"):
    raise SystemExit("Notification worker is not running.")
if config.get("Cmd") != ["python", "-m", "app.workers.notifications"]:
    raise SystemExit("Notification container is not running the FCM worker.")
if (config.get("Labels") or {}).get("org.opencontainers.image.revision") != sys.argv[1]:
    raise SystemExit("Notification worker revision does not match the deployment.")
print("NoWave notification worker and revision verified; delivery requires an FCM acceptance check.")
' "$expected"
