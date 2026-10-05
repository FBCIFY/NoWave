#!/usr/bin/env bash
# Run from an exact, already tested source archive on the NoWave VPS.
set -euo pipefail
umask 077
revision=${1:?Pass the exact tested Git SHA}
[[ $revision =~ ^[a-f0-9]{40}$ ]] || { echo 'A full Git SHA is required.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run as root on the VPS.' >&2; exit 1; }
source_root=$(cd "$(dirname "$0")/../.." && pwd)
root=/opt/nowave
python3 "$source_root/deploy/hostinger/bootstrap.py"
exec 9>"$root/deploy.lock"
flock -n 9 || { echo 'Another NoWave deployment is running.' >&2; exit 1; }
# Refuse missing credentials before replacing any running service.
python3 - "$root/secrets/firebase_service_account.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file():
    raise SystemExit('Firebase service account is missing; deployment was not activated.')
s = json.loads(p.read_text())
if s.get('type') != 'service_account' or s.get('project_id') != 'blueway-dev' or not s.get('private_key'):
    raise SystemExit('Expected a service account for blueway-dev.')
PY
chown root:10001 "$root/secrets/firebase_service_account.json"
chmod 0440 "$root/secrets/firebase_service_account.json"
# Storage settings live outside release.env so deployments never overwrite them.
for required in "$root/config/photo-storage.env" "$root/secrets/scaleway_access_key" "$root/secrets/scaleway_secret_key"; do
  [[ -s "$required" ]] || { echo 'Scaleway photo configuration is missing; deployment was not activated.' >&2; exit 1; }
done
chown root:10001 "$root/secrets/scaleway_access_key" "$root/secrets/scaleway_secret_key"
chmod 0440 "$root/secrets/scaleway_access_key" "$root/secrets/scaleway_secret_key"
for component in api web postgres; do
  image="nowave-$component:$revision"
  [[ $(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image") == "$revision" ]]
done
[[ -f "$source_root/test-results/production-audit-ok" ]] || { echo 'Missing successful image audit evidence.' >&2; exit 1; }
[[ $(cat "$source_root/test-results/production-audit-ok") == "$revision" ]]
if [[ -f "$root/config/release.env" ]]; then
  bash "$source_root/deploy/hostinger/backup.sh"
  cp "$root/config/release.env" "$root/config/release.rollback.env"
  cp "$root/config/compose.yaml" "$root/config/compose.rollback.yaml"
fi
cp "$source_root/deploy/compose.yaml" "$root/config/compose.yaml"
printf 'NOWAVE_VERSION=%s\n' "$revision" > "$root/config/release.env"
compose=(docker compose --env-file "$root/config/release.env" -f "$root/config/compose.yaml" --profile api)
rollback() {
  status=$?
  trap - ERR
  echo 'Deployment failed. Database backup is preserved; no automatic data restore.' >&2
  if [[ -f "$root/config/release.rollback.env" ]]; then
    "${compose[@]}" stop photo-cleanup || true
    cp "$root/config/release.rollback.env" "$root/config/release.env"
    cp "$root/config/compose.rollback.yaml" "$root/config/compose.yaml"
    "${compose[@]}" up -d --wait api web || true
    if "${compose[@]}" config --services | grep -qx photo-cleanup; then
      "${compose[@]}" up -d --wait photo-cleanup || true
    fi
  fi
  exit "$status"
}
trap rollback ERR
"${compose[@]}" up -d --wait --wait-timeout 120 database
"${compose[@]}" run --rm --no-deps migrate
"${compose[@]}" up -d --wait --wait-timeout 90 api web photo-cleanup
bash "$source_root/deploy/hostinger/verify.sh" http://127.0.0.1:18080 "$revision"
printf '%s\n' "$revision" > "$root/current-revision"
install -m 0700 "$source_root/deploy/hostinger/backup.sh" "$root/config/backup.sh"
install -m 0644 "$source_root/deploy/hostinger/nowave-backup.service" /etc/systemd/system/nowave-backup.service
install -m 0644 "$source_root/deploy/hostinger/nowave-backup.timer" /etc/systemd/system/nowave-backup.timer
systemctl daemon-reload
systemctl enable --now nowave-backup.timer
trap - ERR
printf 'NoWave is healthy on the private origin. Enable the validated tunnel to publish.\n'
