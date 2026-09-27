#!/usr/bin/env bash
set -euo pipefail
revision=${1:?Pass the exact Git SHA}
[[ $revision =~ ^[a-f0-9]{40}$ ]] || exit 1
cd "$(dirname "$0")/../.."
mkdir -p test-results/containers
scan_dir=$(cd test-results/containers && pwd)
scanner=aquasec/trivy@sha256:7cced7cae583819fc7806d4cbc0dbbc7cad18b99f7d3e235192e6da8c091045c
rm -f test-results/production-audit-ok
for component in api web postgres tunnel; do
  docker build --platform linux/amd64 --pull --build-arg "NOWAVE_VERSION=$revision" -f "deploy/$component/Dockerfile" -t "nowave-$component:$revision" .
  docker save -o "$scan_dir/$component.tar" "nowave-$component:$revision"
  vex=()
  if [[ "$component" == tunnel ]]; then vex=(--vex /vex/GO-2026-5932.openvex.json); fi
  docker run --rm -v "$scan_dir:/scan" -v "$PWD/deploy/tunnel:/vex:ro" "$scanner" image \
    "${vex[@]}" --input "/scan/$component.tar" --cache-dir /scan/cache --scanners vuln \
    --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 --no-progress \
    --skip-version-check --format json --output "/scan/$component.json"
done
docker run --rm -v "$PWD/deploy:/workspace:ro" "$scanner" config \
  --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL --exit-code 1 --skip-version-check /workspace
printf '%s\n' "$revision" > test-results/production-audit-ok
