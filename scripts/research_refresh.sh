#!/usr/bin/env bash
set -euo pipefail

CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FILE="$CONTROL_DIR/research/sources.json"
OUT_DIR="$CONTROL_DIR/research/processed"
IDEA_DIR="$CONTROL_DIR/idea_bank"
SHARED="$CONTROL_DIR/shared-context"

mkdir -p "$OUT_DIR" "$IDEA_DIR" "$SHARED"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ research_refresh: python3 not found, skip"
  exit 0
fi

python3 "$CONTROL_DIR/scripts/research_refresh.py" \
  --sources "$SRC_FILE" \
  --out-json "$OUT_DIR/signals.json" \
  --out-jsonl "$IDEA_DIR/inbox.jsonl" \
  --out-md "$SHARED/SIGNALS.md" || {
    echo "⚠ research_refresh: failed (best-effort)"
    exit 0
  }

echo "✅ research_refresh: updated signals + inbox"
