#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INPUT="${1:-$ROOT/data/cassis/features.geojson}"
OUTPUT="${2:-$ROOT/tiles/vector/cassis.mbtiles}"
LAYER="${3:-nowave}"
[[ "$LAYER" == nowave ]] || { echo "source-layer must be nowave" >&2; exit 1; }
PROFILE="${4:-}"
if [[ -z "$PROFILE" ]]; then
  if [[ "$(realpath -m "$INPUT")" == "$ROOT/data/cassis/features.geojson" &&
        "$(realpath -m "$OUTPUT")" == "$ROOT/tiles/vector/cassis.mbtiles" ]]; then
    PROFILE=cassis
  else
    echo "Specify build profile explicitly: INPUT OUTPUT nowave cassis|regional" >&2
    exit 1
  fi
fi
case "$PROFILE" in
  cassis)
    # Fixed historical recipe: environment zoom overrides cannot change Cassis.
    MIN_ZOOM=6
    MAX_ZOOM=18
    PROFILE_OPTIONS=(--no-line-simplification --no-tiny-polygon-reduction
                     --no-feature-limit --no-tile-size-limit)
    ;;
  regional)
    MIN_ZOOM="${MIN_ZOOM:-6}"
    MAX_ZOOM="${MAX_ZOOM:-14}"
    # Keep points at every zoom. Simplify geometry only below maxzoom.
    # Exceeding a limit fails the build rather than silently dropping seamarks.
    PROFILE_OPTIONS=(--drop-rate=1 --base-zoom="$MIN_ZOOM" --simplify-only-low-zooms
                     --full-detail=12 --minimum-detail=12
                     --maximum-tile-bytes=500000 --maximum-tile-features=200000)
    ;;
  *) echo "Unknown build profile: $PROFILE" >&2; exit 1 ;;
esac
[[ "$MIN_ZOOM" =~ ^(0|[1-9][0-9]?)$ && "$MAX_ZOOM" =~ ^(0|[1-9][0-9]?)$ ]] &&
  (( MIN_ZOOM <= MAX_ZOOM && MAX_ZOOM <= 22 )) || {
    echo "Expected 0 <= MIN_ZOOM <= MAX_ZOOM <= 22" >&2; exit 1;
  }

command -v tippecanoe >/dev/null 2>&1 || {
  echo "Erreur: tippecanoe n'est pas installé." >&2
  exit 1
}
TIPPECANOE_VERSION="$(tippecanoe --version 2>&1)"

mkdir -p "$(dirname "$OUTPUT")"

TEMP_OUTPUT="$(mktemp "${OUTPUT}.XXXXXXXX.mbtiles")"
trap 'rm -f "$TEMP_OUTPUT"' EXIT

tippecanoe \
  --output="$TEMP_OUTPUT" \
  --layer="$LAYER" \
  --minimum-zoom="$MIN_ZOOM" \
  --maximum-zoom="$MAX_ZOOM" \
  "${PROFILE_OPTIONS[@]}" \
  --force \
  "$INPUT"

python3 - "$INPUT" "$TEMP_OUTPUT" "$PROFILE" "$TIPPECANOE_VERSION" "$MIN_ZOOM" "$MAX_ZOOM" <<'PYCODE'
import hashlib, sqlite3, sys
h = hashlib.sha256()
with open(sys.argv[1], 'rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        h.update(chunk)
with sqlite3.connect(sys.argv[2]) as db:
    db.executemany("INSERT OR REPLACE INTO metadata(name,value) VALUES (?,?)", [
        ('nowave:input_sha256', h.hexdigest()), ('nowave:build_profile', sys.argv[3]),
        ('nowave:tippecanoe_version', sys.argv[4]),
        ('nowave:minzoom', sys.argv[5]), ('nowave:maxzoom', sys.argv[6])])
PYCODE
mv "$TEMP_OUTPUT" "$OUTPUT"

echo
echo "OK - MBTiles généré"
echo "Entrée : $INPUT"
echo "Sortie : $OUTPUT"
