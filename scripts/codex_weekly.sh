#!/usr/bin/env bash
set -euo pipefail
CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_FILE="$CONTROL_DIR/system/prompts/weekly_run.md"

if ! command -v codex >/dev/null 2>&1; then
  echo "❌ codex command not found. Install/enable Codex CLI first."
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "❌ weekly prompt file not found: $PROMPT_FILE"
  exit 1
fi

echo "▶ running weekly prompt via codex exec (stdin) ..."
cat "$PROMPT_FILE" | codex exec -
