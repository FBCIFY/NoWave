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
