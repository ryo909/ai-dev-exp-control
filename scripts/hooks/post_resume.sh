#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
echo "post_resume: done"
echo "post_resume: generating weekly digest..."
bash "$CONTROL_DIR/scripts/report_weekly_digest.sh" || true
echo "post_resume: updating source stats..."
bash "$CONTROL_DIR/scripts/update_sources_stats.sh" || true
echo "post_resume: building control tower digest..."
bash "$CONTROL_DIR/scripts/build_control_tower_digest.sh" || true
echo "post_resume: building next batch plan..."
bash "$CONTROL_DIR/scripts/build_next_batch_plan.sh" || true
