#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INPUT="${1:-$ROOT/data/cassis/features.geojson}"
OUTPUT="${2:-$ROOT/tiles/vector/cassis.mbtiles}"
LAYER="${3:-nowave}"

command -v tippecanoe >/dev/null 2>&1 || {
  echo "Erreur: tippecanoe n'est pas installé." >&2
  exit 1
}

mkdir -p "$(dirname "$OUTPUT")"

tippecanoe \
  --output="$OUTPUT" \
  --layer="$LAYER" \
  --minimum-zoom=6 \
  --maximum-zoom=18 \
  --no-line-simplification \
  --no-tiny-polygon-reduction \
  --no-feature-limit \
  --no-tile-size-limit \
  --force \
  "$INPUT"

echo
echo "OK - MBTiles généré"
echo "Entrée : $INPUT"
echo "Sortie : $OUTPUT"
