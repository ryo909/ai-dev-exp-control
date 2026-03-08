#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TODAY="${DATE_OVERRIDE:-$(date +%F)}"

python3 "$SCRIPT_DIR/evaluate_portfolio.py" --control-dir "$CONTROL_DIR" --date "$TODAY" "$@" || true

JSON_PATH="$CONTROL_DIR/reports/portfolio/portfolio_eval_${TODAY}.json"
MD_PATH="$CONTROL_DIR/reports/portfolio/portfolio_eval_${TODAY}.md"

[ -f "$JSON_PATH" ] && echo "[evaluate_portfolio] artifact: ${JSON_PATH#$CONTROL_DIR/}"
[ -f "$MD_PATH" ] && echo "[evaluate_portfolio] artifact: ${MD_PATH#$CONTROL_DIR/}"
