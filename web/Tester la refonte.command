#!/bin/bash
# Local, read-only preview. Only the processes started here are stopped on exit.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

nowave_web="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nowave_root="$(cd "$nowave_web/.." && pwd)"
nowave_original="$nowave_root"
if nowave_git_common="$(git -C "$nowave_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  nowave_original="$(dirname "$nowave_git_common")"
fi

fail() { printf '\n%s\n' "$1" >&2; exit 1; }
if [[ "${NOWAVE_ENV:-}" == production ]]; then
  fail "Cet aperçu est local. Relancez-le sans NOWAVE_ENV=production."
fi

nowave_python=""
for nowave_candidate in "${NOWAVE_PREVIEW_PYTHON:-}" "$nowave_root/.venv/bin/python" "$nowave_original/.venv/bin/python" "$nowave_root/backend/.venv/bin/python" "$nowave_original/backend/.venv/bin/python" python3.13 python3.12 python3; do
  [[ -n "$nowave_candidate" ]] || continue
  if PYTHONPATH="$nowave_root/backend" "$nowave_candidate" -c 'import sys; assert sys.version_info >= (3, 12); import uvicorn; from app.main import app' >/dev/null 2>&1; then
    nowave_python="$nowave_candidate"
    break
  fi
done
[[ -n "$nowave_python" ]] || fail "Python 3.12+ avec les dépendances backend est introuvable. Activez l’environnement du projet ou définissez NOWAVE_PREVIEW_PYTHON=/chemin/.venv/bin/python. Aucun paquet Python n’a été installé."
command -v node >/dev/null 2>&1 || fail "Node.js est nécessaire pour ouvrir la landing locale."
command -v npm >/dev/null 2>&1 || fail "npm est nécessaire pour préparer la landing locale."
node -e 'const [major,minor]=process.versions.node.split(".").map(Number); process.exit((major===20&&minor>=19)||(major===22&&minor>=12)||major>22?0:1)' || fail "Utilisez Node.js 20.19+ (branche 20) ou 22.12+."

if [[ -z "${NOWAVE_MAPBOX_CONFIG:-}" ]]; then
  for nowave_config in "$nowave_root/mobile/.env.json" "$nowave_original/mobile/.env.json"; do
    if [[ -f "$nowave_config" ]]; then
      export NOWAVE_MAPBOX_CONFIG="$nowave_config"
      break
    fi
  done
fi
# preview.py reads only MAPBOX_ACCESS_TOKEN from this file and accepts pk.* only.
if [[ -n "${NOWAVE_MAPBOX_CONFIG:-}" && ! -f "$NOWAVE_MAPBOX_CONFIG" ]]; then
  fail "Le fichier indiqué par NOWAVE_MAPBOX_CONFIG est introuvable."
fi

cd "$nowave_web"
if [[ ! -f node_modules/vite/bin/vite.js ]]; then
  printf 'Préparation des dépendances web du projet…\n'
  npm ci --no-audit --no-fund
fi

free_port() {
  "$nowave_python" - "$1" <<'PY'
import socket
import sys
try:
    first = int(sys.argv[1])
    if not 1024 <= first <= 65535:
        raise ValueError()
except ValueError:
    sys.exit('Les ports locaux doivent être compris entre 1024 et 65535.')
for port in range(first, min(first + 100, 65536)):
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            continue
        print(port)
        break
else:
    sys.exit('Aucun port libre trouvé. Choisissez un autre port de départ.')
PY
}
nowave_api_port="$(free_port "${NOWAVE_PREVIEW_API_PORT:-8000}")"
nowave_web_port="$(free_port "${NOWAVE_PREVIEW_WEB_PORT:-5173}")"
if [[ "$nowave_api_port" == "$nowave_web_port" ]]; then
  nowave_web_port="$(free_port "$((nowave_web_port + 1))")"
fi
nowave_logs="$(mktemp -d "${TMPDIR:-/tmp}/nowave-preview.XXXXXX")"
nowave_api_pid=""
nowave_web_pid=""
cleanup() {
  [[ -z "$nowave_api_pid" ]] || kill "$nowave_api_pid" 2>/dev/null || true
  [[ -z "$nowave_web_pid" ]] || kill "$nowave_web_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

printf 'Démarrage de l’aperçu local avec des données fictives…\n'
(
  cd "$nowave_root"
  export PYTHONPATH="$nowave_root/backend"
  exec "$nowave_python" backend/tests/browser/preview.py --port "$nowave_api_port"
) >"$nowave_logs/admin.log" 2>&1 &
nowave_api_pid=$!
NOWAVE_API_URL="http://127.0.0.1:$nowave_api_port" node node_modules/vite/bin/vite.js --host 127.0.0.1 --port "$nowave_web_port" --strictPort >"$nowave_logs/web.log" 2>&1 &
nowave_web_pid=$!

# Verify both services, including Vite's API proxy, before opening any page.
if ! "$nowave_python" - "$nowave_api_port" "$nowave_web_port" "$nowave_api_pid" "$nowave_web_pid" <<'PY'
import json
import os
import signal
import sys
import time
from urllib.request import urlopen
signal.signal(signal.SIGINT, lambda *_: sys.exit(130))
api, web, api_pid, web_pid = map(int, sys.argv[1:])
def preview_response(url):
    with urlopen(url, timeout=2) as response:
        if response.headers.get('X-NoWave-Preview') != 'synthetic-read-only':
            raise ValueError('Ce service n’est pas notre aperçu synthétique.')
        return json.load(response)
deadline = time.monotonic() + 90
while time.monotonic() < deadline:
    try:
        os.kill(api_pid, 0)
        os.kill(web_pid, 0)
    except ProcessLookupError:
        sys.exit('Un serveur local ne s’est pas lancé.')
    try:
        preview_response(f'http://127.0.0.1:{api}/api/v1/map/web-config')
        preview_response(f'http://127.0.0.1:{web}/api/v1/map/web-config')
        with urlopen(f'http://127.0.0.1:{web}/', timeout=2) as response:
            html = response.read(200000).decode()
        if 'id="journey-map"' not in html or 'id="carte"' not in html:
            raise ValueError('La landing NoWave attendue est absente.')
        break
    except (OSError, ValueError):
        time.sleep(0.4)
else:
    sys.exit('L’aperçu n’est pas prêt après 90 secondes.')
PY
then
  printf '\nImpossible de démarrer l’aperçu. Journaux locaux : %s\n' "$nowave_logs" >&2
  tail -n 12 "$nowave_logs/admin.log" "$nowave_logs/web.log" >&2
  exit 1
fi

nowave_url="http://127.0.0.1:$nowave_web_port"
printf '\nLanding : %s\nAdministration : %s/admin\n' "$nowave_url" "$nowave_url"
printf 'Compte de démonstration : admin@nowave.test / preview-only\n'
printf 'Les données sont fictives et les modifications sont désactivées.\n'
printf 'Gardez cette fenêtre ouverte. Ctrl+C arrête uniquement cet aperçu.\n'
if [[ "${NOWAVE_PREVIEW_NO_OPEN:-0}" != 1 ]] && command -v open >/dev/null 2>&1; then
  open "$nowave_url"
fi
while kill -0 "$nowave_api_pid" 2>/dev/null && kill -0 "$nowave_web_pid" 2>/dev/null; do
  sleep 2
done
fail "Un serveur s’est arrêté. Consultez les journaux dans $nowave_logs."
