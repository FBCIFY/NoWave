#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/opt/nowave
cd "$root/config"
[[ -f release.env ]] || exit 0
stamp=$(date -u +%Y%m%dT%H%M%SZ)
# The timer and a deployment can run in the same second. Never share a dump,
# even when the caller does not hold the systemd backup lock.
directory=$(mktemp -d "$root/backups/$stamp.XXXXXX")
cleanup() {
  if [[ -n "$directory" ]]; then rm -rf -- "$directory"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
compose=(docker compose --env-file release.env -f compose.yaml)
"${compose[@]}" exec -T database pg_dump -U nowave_owner -d nowave -Fc > "$directory/database.dump.partial"
"${compose[@]}" exec -T database pg_restore --list < "$directory/database.dump.partial" > /dev/null
cp compose.yaml release.env "$directory/"
if [[ -f photo-storage.env ]]; then cp photo-storage.env "$directory/"; fi
"${compose[@]}" logs --no-color --since 24h > "$directory/services.log" 2>&1
# Consumers only see database.dump once all backup steps have succeeded.
mv "$directory/database.dump.partial" "$directory/database.dump"
completed=$directory
directory=''
printf 'Private backup created: %s\n' "$completed"
