#!/usr/bin/env bash
set -euo pipefail

CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IN_JSON="$CONTROL_DIR/research/processed/signals.json"
OUT_JSON="$CONTROL_DIR/idea_bank/shortlist.json"
mkdir -p "$(dirname "$OUT_JSON")"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ idea_shortlist: python3 not found, skip"
  exit 0
fi

if [ ! -f "$IN_JSON" ]; then
  echo "⚠ idea_shortlist: signals.json not found, skip"
  exit 0
fi

python3 "$CONTROL_DIR/scripts/idea_shortlist.py" --in-json "$IN_JSON" --out-json "$OUT_JSON" --limit 30 || {
  echo "⚠ idea_shortlist: failed (best-effort)"
  exit 0
}
echo "✅ idea_shortlist: updated $OUT_JSON"
