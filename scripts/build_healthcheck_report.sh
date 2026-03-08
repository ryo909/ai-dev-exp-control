#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/build_healthcheck_report.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
for f in \
  "$CONTROL_DIR/reports/healthcheck/healthcheck_${DATE_STR}.json" \
  "$CONTROL_DIR/reports/healthcheck/healthcheck_${DATE_STR}.md"; do
  [ -f "$f" ] && echo "[build_healthcheck_report] artifact: ${f#$CONTROL_DIR/}"
done
