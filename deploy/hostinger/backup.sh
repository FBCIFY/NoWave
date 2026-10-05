#!/usr/bin/env bash
set -euo pipefail
umask 077
root=/opt/nowave
cd "$root/config"
[[ -f release.env ]] || exit 0
stamp=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$root/backups/$stamp"
compose=(docker compose --env-file release.env -f compose.yaml)
"${compose[@]}" exec -T database pg_dump -U nowave_owner -d nowave -Fc > "$root/backups/$stamp/database.dump"
"${compose[@]}" exec -T database pg_restore --list < "$root/backups/$stamp/database.dump" > /dev/null
cp compose.yaml release.env "$root/backups/$stamp/"
if [[ -f photo-storage.env ]]; then cp photo-storage.env "$root/backups/$stamp/"; fi
"${compose[@]}" logs --no-color --since 24h > "$root/backups/$stamp/services.log" 2>&1
printf 'Private backup created: %s\n' "$root/backups/$stamp"
