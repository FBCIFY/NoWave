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
    # A healthy database does not prove that public marine layers work.
    # Use three fixed, valid Toulon tiles, one request per family; never retry
    # individual public-provider requests or generate navigation-sized bursts.
    # Any non-2xx answer (notably 429/503) blocks promotion and invokes rollback.
    marine_ok=true
    for tile in \
      seamarks/12/2115/1503.pbf \
      soundings/12/2115/1503.pbf \
      bathymetry/12/2115/1503.png; do
      if ! curl --fail --silent --show-error --max-time 20 \
           --output /dev/null "https://api.no-wave.fr/api/v1/map/$tile"; then
        echo "Marine public smoke check failed for $tile" >&2
        marine_ok=false
        break
      fi
    done
    if [[ "$marine_ok" == true ]]; then
      exit 0
    fi
  fi
  sleep 5
done
echo 'Public production verification failed; deployment must be rolled back.' >&2
exit 1
