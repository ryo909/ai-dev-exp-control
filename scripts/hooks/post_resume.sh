#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "post_resume: done"
echo "post_resume: generating weekly digest..."
bash "$CONTROL_DIR/scripts/report_weekly_digest.sh" || true
