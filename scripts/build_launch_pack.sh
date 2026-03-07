#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/build_launch_pack.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
JSON_PATH="$CONTROL_DIR/reports/launch/launch_pack_${DATE_STR}.json"
MD_PATH="$CONTROL_DIR/reports/launch/launch_pack_${DATE_STR}.md"

[ -f "$JSON_PATH" ] && echo "[build_launch_pack] artifact: ${JSON_PATH#$CONTROL_DIR/}"
[ -f "$MD_PATH" ] && echo "[build_launch_pack] artifact: ${MD_PATH#$CONTROL_DIR/}"
