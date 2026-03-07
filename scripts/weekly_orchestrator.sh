#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_FILE="$CONTROL_DIR/system/adoption_profiles.json"

DRY_RUN="${DRY_RUN:-0}"
STAGE="${STAGE:-all}"
ADOPTION_PROFILE="${ADOPTION_PROFILE:-safe}"
TODAY="$(date +%F)"

USE_NEXT_BATCH_PLAN="0"
ADOPT_NEXT_BATCH_COMPLEXITY="0"
ADOPT_NEXT_BATCH_COMPONENTS="0"
ADOPT_NEXT_BATCH_ENHANCEMENT="0"

STAGES_RUN=()
RESUME_EXECUTED="false"

log() { echo "[weekly_orchestrator] $*"; }

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

run_best_effort() {
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN(best-effort): $*"
    return 0
  fi
  "$@" || true
}

load_profile() {
  if [ -f "$PROFILE_FILE" ]; then
    USE_NEXT_BATCH_PLAN=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].USE_NEXT_BATCH_PLAN // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_NEXT_BATCH_COMPLEXITY=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_NEXT_BATCH_COMPLEXITY // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_NEXT_BATCH_COMPONENTS=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_NEXT_BATCH_COMPONENTS // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_NEXT_BATCH_ENHANCEMENT=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_NEXT_BATCH_ENHANCEMENT // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
  fi
}

stage_preflight() {
  STAGES_RUN+=("preflight")
  log "stage=preflight"
  local req=(
    "$CONTROL_DIR/STATE.json"
    "$CONTROL_DIR/scripts/resume.sh"
    "$CONTROL_DIR/scripts/research_refresh.sh"
    "$CONTROL_DIR/scripts/idea_shortlist.sh"
    "$CONTROL_DIR/scripts/build_control_tower_digest.sh"
    "$CONTROL_DIR/scripts/build_next_batch_plan.sh"
  )
  for f in "${req[@]}"; do
    if [ -e "$f" ]; then
      log "ok: ${f#$CONTROL_DIR/}"
    else
      log "missing: ${f#$CONTROL_DIR/}"
    fi
  done
  (cd "$CONTROL_DIR" && git status -sb || true)
  (cd "$CONTROL_DIR" && git branch --show-current || true)
  if [ "$DRY_RUN" = "1" ]; then
    log "planned stages: preflight -> intel -> thesis -> run -> report"
  fi
}

stage_intel() {
  STAGES_RUN+=("intel")
  log "stage=intel"
  run_best_effort bash "$CONTROL_DIR/scripts/research_refresh.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/idea_shortlist.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_control_tower_digest.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_next_batch_plan.sh"
  log "artifacts: shared-context/SIGNALS.md, idea_bank/shortlist.json, reports/control_tower/*, plans/next_batch_plan.json"
}

stage_thesis() {
  STAGES_RUN+=("thesis")
  log "stage=thesis"
  run_best_effort bash "$CONTROL_DIR/scripts/build_thesis_update_draft.sh" --date "$TODAY"
}

stage_run() {
  STAGES_RUN+=("run")
  log "stage=run"
  load_profile
  log "adoption profile=${ADOPTION_PROFILE} flags: USE_NEXT_BATCH_PLAN=${USE_NEXT_BATCH_PLAN}, ADOPT_NEXT_BATCH_COMPLEXITY=${ADOPT_NEXT_BATCH_COMPLEXITY}, ADOPT_NEXT_BATCH_COMPONENTS=${ADOPT_NEXT_BATCH_COMPONENTS}, ADOPT_NEXT_BATCH_ENHANCEMENT=${ADOPT_NEXT_BATCH_ENHANCEMENT}"

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN: env USE_NEXT_BATCH_PLAN=${USE_NEXT_BATCH_PLAN} ADOPT_NEXT_BATCH_COMPLEXITY=${ADOPT_NEXT_BATCH_COMPLEXITY} ADOPT_NEXT_BATCH_COMPONENTS=${ADOPT_NEXT_BATCH_COMPONENTS} ADOPT_NEXT_BATCH_ENHANCEMENT=${ADOPT_NEXT_BATCH_ENHANCEMENT} bash scripts/resume.sh"
    return 0
  fi

  USE_NEXT_BATCH_PLAN="$USE_NEXT_BATCH_PLAN" \
  ADOPT_NEXT_BATCH_COMPLEXITY="$ADOPT_NEXT_BATCH_COMPLEXITY" \
  ADOPT_NEXT_BATCH_COMPONENTS="$ADOPT_NEXT_BATCH_COMPONENTS" \
  ADOPT_NEXT_BATCH_ENHANCEMENT="$ADOPT_NEXT_BATCH_ENHANCEMENT" \
  bash "$CONTROL_DIR/scripts/resume.sh"
  RESUME_EXECUTED="true"
}

stage_report() {
  STAGES_RUN+=("report")
  log "stage=report"
  run_best_effort bash "$CONTROL_DIR/scripts/build_control_tower_digest.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_next_batch_plan.sh"

  local stages_csv
  stages_csv=$(IFS=,; echo "${STAGES_RUN[*]}")
  local flags_json
  flags_json=$(jq -nc \
    --arg u "$USE_NEXT_BATCH_PLAN" \
    --arg c "$ADOPT_NEXT_BATCH_COMPLEXITY" \
    --arg s "$ADOPT_NEXT_BATCH_COMPONENTS" \
    --arg e "$ADOPT_NEXT_BATCH_ENHANCEMENT" \
    '{USE_NEXT_BATCH_PLAN:$u,ADOPT_NEXT_BATCH_COMPLEXITY:$c,ADOPT_NEXT_BATCH_COMPONENTS:$s,ADOPT_NEXT_BATCH_ENHANCEMENT:$e}')

  run_best_effort bash "$CONTROL_DIR/scripts/build_weekly_run_report.sh" \
    --date "$TODAY" \
    --adoption-profile "$ADOPTION_PROFILE" \
    --dry-run "$DRY_RUN" \
    --stages "$stages_csv" \
    --resume-executed "$RESUME_EXECUTED" \
    --flags-json "$flags_json"
}

load_profile

case "$STAGE" in
  all)
    stage_preflight
    stage_intel
    stage_thesis
    stage_run
    stage_report
    ;;
  preflight) stage_preflight ;;
  intel) stage_intel ;;
  thesis) stage_thesis ;;
  run) stage_run ;;
  report) stage_report ;;
  *)
    echo "Unknown STAGE=$STAGE (expected: all|preflight|intel|thesis|run|report)" >&2
    exit 1
    ;;
esac

log "done"
