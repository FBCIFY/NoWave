#!/usr/bin/env bash
set -euo pipefail
revision=${1:?Pass the exact Git SHA}
[[ $revision =~ ^[a-f0-9]{40}$ ]] || exit 1
cd "$(dirname "$0")/../.."
mkdir -p test-results/containers
scan_dir=$(cd test-results/containers && pwd)
scanner=aquasec/trivy@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c
rm -f test-results/production-audit-ok
# Keep audit evidence, but discard the database/cache and image exports on every
# exit. A private workspace also prevents one run from cleaning another's files.
work_dir=$(mktemp -d "$scan_dir/.audit-XXXXXX")
# GitHub runners are not root; keep mounted cache files removable by their owner.
scan_user="$(id -u):$(id -g)"
cleanup() { rm -rf -- "$work_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Trivy's built-in registry fallback does not cover every download error (404
# included). Retry only database preparation, never a failed security audit.
db_ready=false
for repository in mirror.gcr.io/aquasec/trivy-db:2 ghcr.io/aquasecurity/trivy-db:2; do
  printf 'Preparing Trivy vulnerability database from %s\n' "$repository"
  if docker run --rm --user "$scan_user" -v "$work_dir:/scan" "$scanner" image \
      --cache-dir /scan/cache --db-repository "$repository" --download-db-only \
      --no-progress --skip-version-check; then
    db_ready=true
    break
  fi
  printf 'Trivy database preparation failed for %s\n' "$repository" >&2
done
if [[ "$db_ready" != true ]]; then
  echo 'No Trivy database source succeeded; refusing to build and deploy unaudited images.' >&2
  exit 1
fi
for component in api web postgres tunnel; do
  docker build --platform linux/amd64 --pull --build-arg "NOWAVE_VERSION=$revision" -f "deploy/$component/Dockerfile" -t "nowave-$component:$revision" .
  docker save -o "$work_dir/$component.tar" "nowave-$component:$revision"
  scan_options=(--skip-db-update --scanners vuln)
  if [[ "$component" == tunnel ]]; then scan_options+=(--vex /vex/GO-2026-5932.openvex.json); fi
  docker run --rm --user "$scan_user" -v "$work_dir:/scan" -v "$scan_dir:/reports" -v "$PWD/deploy/tunnel:/vex:ro" "$scanner" image \
    "${scan_options[@]}" --input "/scan/$component.tar" --cache-dir /scan/cache \
    --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 --no-progress \
    --skip-version-check --format json --output "/reports/$component.json"
  rm -f -- "$work_dir/$component.tar"
done
docker run --rm -v "$PWD/deploy:/workspace:ro" "$scanner" config \
  --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 --skip-version-check /workspace
printf '%s\n' "$revision" > test-results/production-audit-ok
