#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/build_growth_brief.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
JSON_PATH="$CONTROL_DIR/reports/growth/growth_brief_${DATE_STR}.json"
MD_PATH="$CONTROL_DIR/reports/growth/growth_brief_${DATE_STR}.md"

[ -f "$JSON_PATH" ] && echo "[build_growth_brief] artifact: ${JSON_PATH#$CONTROL_DIR/}"
[ -f "$MD_PATH" ] && echo "[build_growth_brief] artifact: ${MD_PATH#$CONTROL_DIR/}"
