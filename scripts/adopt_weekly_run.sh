#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
python3 "$SCRIPT_DIR/adopt_weekly_run.py" --control-dir "$CONTROL_DIR" "$@"
