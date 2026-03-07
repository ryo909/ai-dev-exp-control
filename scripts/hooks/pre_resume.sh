#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "pre_resume: refresh research signals + shortlist (best-effort)"
bash "$CONTROL_DIR/scripts/research_refresh.sh" || true
bash "$CONTROL_DIR/scripts/idea_shortlist.sh" || true
