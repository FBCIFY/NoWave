#!/usr/bin/env bash
set -euo pipefail
base=${1:-http://127.0.0.1:18080}
expected=${2:?Expected revision required}
request() { curl --silent --show-error --max-time 15 -H 'Host: no-wave.fr' "$@"; }
request --fail "$base/version.json" | python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$expected"
[[ $(request -o /dev/null -w '%{http_code}' -H 'Origin: https://untrusted.example' "$base/") == 403 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' -H 'Host: untrusted.example' "$base/") == 421 ]]
request --fail "$base/brand/nowave-icon.svg?v=vector-3" > /dev/null
if [[ ${NOWAVE_VERIFY_API:-1} == 1 ]]; then
  request --fail "$base/health/ready" | python3 -c 'import json,sys; assert json.load(sys.stdin)["database"] == "ok"'
  request --fail "$base/version" | python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$expected"
  [[ $(request -o /dev/null -w '%{http_code}' "$base/api/v1/users/me") == 401 ]]
  [[ $(request -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer invalid' "$base/api/v1/users/me") == 401 ]]
fi
printf 'NoWave revision, routes and security boundaries verified.\n'
