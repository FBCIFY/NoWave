#!/bin/bash
set -e
cd -- "$(dirname -- "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v node >/dev/null 2>&1; then
  printf 'NoWave nécessite Node.js 22.12+ ou 24 LTS. Installez-le depuis https://nodejs.org, puis relancez ce fichier.\n'
  read -r -p 'Appuyez sur Entrée pour fermer.'
  exit 1
fi
if [ ! -d node_modules ]; then
  printf 'Installation des dépendances NoWave…\n'
  npm ci --no-fund --no-audit
fi
printf '\nOuverture de NoWave sur http://127.0.0.1:4173\nGardez cette fenêtre ouverte. Ctrl+C pour arrêter le site.\n\n'
exec npm start
