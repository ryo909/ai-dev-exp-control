#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$SCRIPT_DIR/collect_post_launch_feedback.py" --control-dir "$CONTROL_DIR" "$@" || true

DATE_STR="${DATE_OVERRIDE:-$(date +%F)}"
for f in \
  "$CONTROL_DIR/data/feedback/raw/buffer_metrics_${DATE_STR}.json" \
  "$CONTROL_DIR/data/feedback/normalized/post_metrics_${DATE_STR}.json" \
  "$CONTROL_DIR/data/feedback/normalized/post_metrics.jsonl"; do
  [ -f "$f" ] && echo "[collect_post_launch_feedback] artifact: ${f#$CONTROL_DIR/}"
done
