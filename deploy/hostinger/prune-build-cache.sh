#!/usr/bin/env bash
# Only regenerable BuildKit cache; never prune images, volumes, or containers.
set -euo pipefail
exec 9>/opt/nowave/deploy.lock
flock -n 9 || exit 0
docker buildx prune --force --max-used-space 4gb --reserved-space 2gb
