#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/build_launch_exports.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
BASE="$CONTROL_DIR/exports/launch"

for f in \
  "$BASE/launch_export_${DATE_STR}.json" \
  "$BASE/launch_export_${DATE_STR}.md" \
  "$BASE/make_payload_${DATE_STR}.json" \
  "$BASE/note_seed_${DATE_STR}.md" \
  "$BASE/gallery_entries_${DATE_STR}.json" \
  "$BASE/x_queue_${DATE_STR}.json"; do
  [ -f "$f" ] && echo "[build_launch_exports] artifact: ${f#$CONTROL_DIR/}"
done
