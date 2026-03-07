#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/build_post_launch_feedback_digest.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
for f in \
  "$CONTROL_DIR/reports/feedback/post_launch_feedback_${DATE_STR}.json" \
  "$CONTROL_DIR/reports/feedback/post_launch_feedback_${DATE_STR}.md"; do
  [ -f "$f" ] && echo "[build_post_launch_feedback_digest] artifact: ${f#$CONTROL_DIR/}"
done
