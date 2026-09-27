#!/usr/bin/env bash
# Runs on the NoWave VPS after the matching Git archive is transferred by CI.
set -euo pipefail
umask 077
revision=${1:?Pass the validated Git SHA}
[[ $revision =~ ^[a-f0-9]{40}$ ]] || { echo 'A full Git SHA is required.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run as root on the NoWave VPS.' >&2; exit 1; }
source_root="/opt/nowave/releases/$revision"
[[ -f "$source_root/deploy/hostinger/deploy.sh" ]] || { echo 'Release archive is missing.' >&2; exit 1; }
cd "$source_root"

bash deploy/hostinger/build-and-audit.sh "$revision"
bash deploy/hostinger/deploy.sh "$revision"

root=/opt/nowave
[[ -s "$root/secrets/tunnel_token" ]] || { echo 'NoWave tunnel token is missing.' >&2; exit 1; }
install -m 0600 deploy/tunnel.yaml "$root/config/tunnel.yaml"
cd "$root/config"
docker compose --env-file release.env -f compose.yaml -f tunnel.yaml --profile api up -d --wait --wait-timeout 120 tunnel

# Check what users receive through Cloudflare, not only the private origin.
for attempt in {1..12}; do
  if curl --fail --silent --show-error --max-time 15 https://no-wave.fr/version.json |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$revision" &&
     curl --fail --silent --show-error --max-time 15 https://api.no-wave.fr/version |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["version"] == sys.argv[1]' "$revision" &&
     curl --fail --silent --show-error --max-time 15 https://api.no-wave.fr/health/ready |
      python3 -c 'import json,sys; assert json.load(sys.stdin)["database"] == "ok"'; then
    printf 'NoWave %s is live and healthy.\n' "$revision"
    exit 0
  fi
  sleep 5
done
echo 'Public production verification failed; inspect the NoWave tunnel and release.' >&2
exit 1
