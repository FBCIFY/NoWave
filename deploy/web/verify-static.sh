#!/bin/sh
# Runs inside the exact web image with --network none, as its runtime user.
set -eu
nginx -g 'daemon off;' &
server_pid=$!
trap 'kill "$server_pid"; wait "$server_pid" || true' EXIT
attempt=0
until wget -q -T 1 -O /dev/null http://127.0.0.1:8080/health; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || exit 1
    sleep 0.1
done
tile=gebco-2026-v1/6/57/25.webp
wget -S -T 3 --header='Host: api.no-wave.fr' \
    -O /tmp/gebco.webp "http://127.0.0.1:8080/api/v1/map/seafloor/$tile" \
    2>/tmp/gebco-headers
cmp /tmp/gebco.webp "/usr/share/nginx/marine/$tile"
grep -qi 'Content-Type: image/webp' /tmp/gebco-headers
grep -qi 'Cache-Control: max-age=31536000' /tmp/gebco-headers
echo 'GEBCO static tile verified without API or external network.'
