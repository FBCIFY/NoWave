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
[[ -s "$root/secrets/firebase_web_api_key" ]] || { echo 'Firebase Web API key is missing; deployment was not activated.' >&2; exit 1; }
[[ -s "$root/secrets/tunnel_token" ]] || { echo 'NoWave tunnel token is missing; deployment was not activated.' >&2; exit 1; }
chown root:10001 "$root/secrets/firebase_web_api_key"
chmod 0440 "$root/secrets/firebase_web_api_key"
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
previous_release=false
previous_tunnel=false
previous_tunnel_running=false
previous_marker=false
if [[ -f "$root/current-revision" ]]; then
  cp "$root/current-revision" "$root/current-revision.rollback"
  previous_marker=true
fi
if [[ -f "$root/config/release.env" ]]; then
  bash "$source_root/deploy/hostinger/backup.sh"
  cp "$root/config/release.env" "$root/config/release.rollback.env"
  cp "$root/config/compose.yaml" "$root/config/compose.rollback.yaml"
  previous_release=true
  previous_revision=$(sed -n 's/^NOWAVE_VERSION=//p' "$root/config/release.env")
  if [[ -f "$root/config/tunnel.yaml" ]]; then
    cp "$root/config/tunnel.yaml" "$root/config/tunnel.rollback.yaml"
    previous_tunnel=true
    running_tunnel=$(docker compose --env-file "$root/config/release.env" -f "$root/config/compose.yaml" -f "$root/config/tunnel.yaml" --profile api ps --status running -q tunnel)
    if [[ -n "$running_tunnel" ]]; then
      previous_tunnel_running=true
    fi
  fi
fi
compose=(docker compose --env-file "$root/config/release.env" -f "$root/config/compose.yaml" --profile api)
tunnel_activation_started=false
rollback() {
  status=$1
  trap - ERR INT TERM
  rollback_failed=false
  echo 'Deployment failed. Database backup is preserved; no automatic data restore.' >&2
  if [[ "$tunnel_activation_started" == true ]]; then
    "${compose[@]}" -f "$root/config/tunnel.yaml" stop tunnel || rollback_failed=true
  fi
  "${compose[@]}" stop notifications photo-cleanup || rollback_failed=true
  if [[ "$previous_release" == true ]]; then
    if cp "$root/config/release.rollback.env" "$root/config/release.env" &&
       cp "$root/config/compose.rollback.yaml" "$root/config/compose.yaml"; then
      "${compose[@]}" up -d --wait api web || rollback_failed=true
      if restored_services=$("${compose[@]}" config --services); then
        for service in photo-cleanup notifications; do
          if grep -qx "$service" <<< "$restored_services"; then
            "${compose[@]}" up -d --wait "$service" || rollback_failed=true
          fi
        done
      else
        rollback_failed=true
      fi
      if [[ "$previous_tunnel" == true ]]; then
        if cp "$root/config/tunnel.rollback.yaml" "$root/config/tunnel.yaml"; then
          if [[ "$previous_tunnel_running" == true ]]; then
            "${compose[@]}" -f "$root/config/tunnel.yaml" up -d --wait --wait-timeout 120 tunnel || rollback_failed=true
          fi
        else
          rollback_failed=true
        fi
      elif [[ "$tunnel_activation_started" == true ]]; then
        rm -f "$root/config/tunnel.yaml" || rollback_failed=true
      fi
      bash "$source_root/deploy/hostinger/verify.sh" http://127.0.0.1:18080 "$previous_revision" || rollback_failed=true
      if [[ "$previous_tunnel_running" == true ]]; then
        bash "$source_root/deploy/hostinger/verify-public.sh" "$previous_revision" || rollback_failed=true
      fi
    else
      rollback_failed=true
    fi
  else
    "${compose[@]}" stop api web || rollback_failed=true
    rm -f "$root/config/release.env" "$root/config/compose.yaml" || rollback_failed=true
    if [[ "$tunnel_activation_started" == true ]]; then rm -f "$root/config/tunnel.yaml" || rollback_failed=true; fi
  fi
  if [[ "$previous_marker" == true ]]; then
    cp "$root/current-revision.rollback" "$root/current-revision.tmp" &&
      mv "$root/current-revision.tmp" "$root/current-revision" || rollback_failed=true
  else
    rm -f "$root/current-revision" || rollback_failed=true
  fi
  rm -f "$root/current-revision.tmp" || rollback_failed=true
  if [[ "$rollback_failed" == true ]]; then echo 'Rollback incomplete; manual recovery is required.' >&2; fi
  exit "$status"
}
trap 'rollback "$?"' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM
cp "$source_root/deploy/compose.yaml" "$root/config/compose.yaml"
printf 'NOWAVE_VERSION=%s\n' "$revision" > "$root/config/release.env"
"${compose[@]}" up -d --wait --wait-timeout 120 database
"${compose[@]}" run --rm --no-deps migrate
"${compose[@]}" up -d --wait --wait-timeout 90 api web photo-cleanup notifications
bash "$source_root/deploy/hostinger/verify-notifications.sh" "$revision" "$("${compose[@]}" ps -q notifications)"
bash "$source_root/deploy/hostinger/verify.sh" http://127.0.0.1:18080 "$revision"
tunnel_activation_started=true
install -m 0600 "$source_root/deploy/tunnel.yaml" "$root/config/tunnel.yaml"
"${compose[@]}" -f "$root/config/tunnel.yaml" up -d --wait --wait-timeout 120 tunnel
bash "$source_root/deploy/hostinger/verify-public.sh" "$revision" --with-gebco
install -m 0700 "$source_root/deploy/hostinger/backup.sh" "$root/config/backup.sh"
install -m 0644 "$source_root/deploy/hostinger/nowave-backup.service" /etc/systemd/system/nowave-backup.service
install -m 0644 "$source_root/deploy/hostinger/nowave-backup.timer" /etc/systemd/system/nowave-backup.timer
systemctl daemon-reload
systemctl enable --now nowave-backup.timer
install -m 0700 "$source_root/deploy/hostinger/prune-build-cache.sh" "$root/config/prune-build-cache.sh"
install -m 0644 "$source_root/deploy/hostinger/nowave-build-cache.service" /etc/systemd/system/nowave-build-cache.service
install -m 0644 "$source_root/deploy/hostinger/nowave-build-cache.timer" /etc/systemd/system/nowave-build-cache.timer
systemctl daemon-reload
systemctl enable --now nowave-build-cache.timer
printf '%s\n' "$revision" > "$root/current-revision.tmp"
mv "$root/current-revision.tmp" "$root/current-revision"
trap - ERR INT TERM
printf 'NoWave %s is live and healthy.\n' "$revision"
