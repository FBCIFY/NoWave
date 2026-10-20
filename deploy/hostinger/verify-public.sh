#!/usr/bin/env bash
# Read-only checks against the version actually served through the tunnel.
set -euo pipefail
revision=${1:?Pass the expected Git SHA}
for attempt in {1..12}; do
  if curl --fail --silent --show-error --max-time 15 https://no-wave.fr/version.json |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$revision" &&
     curl --fail --silent --show-error --max-time 15 https://api.no-wave.fr/version |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$revision" &&
     curl --fail --silent --show-error --max-time 15 https://api.no-wave.fr/health/ready |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["database"] == "ok"'; then
    exit 0
  fi
  sleep 5
done
echo 'Public production verification failed; deployment must be rolled back.' >&2
exit 1
