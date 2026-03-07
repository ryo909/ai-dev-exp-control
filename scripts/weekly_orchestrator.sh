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
ADOPT_THESIS_DRAFT="0"
ADOPT_WEEKLY_RUN="0"
ADOPT_MEMORY_UPDATES="0"
ADOPT_FEEDBACK_UPDATES="0"
ADOPT_SOURCE_NOTES="0"
ADOPT_LEARNED_RULES="0"

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
    ADOPT_THESIS_DRAFT=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_THESIS_DRAFT // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_WEEKLY_RUN=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_WEEKLY_RUN // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_MEMORY_UPDATES=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_MEMORY_UPDATES // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_FEEDBACK_UPDATES=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_FEEDBACK_UPDATES // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_SOURCE_NOTES=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_SOURCE_NOTES // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
    ADOPT_LEARNED_RULES=$(jq -r --arg p "$ADOPTION_PROFILE" '.[$p].ADOPT_LEARNED_RULES // "0"' "$PROFILE_FILE" 2>/dev/null || echo "0")
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
    "$CONTROL_DIR/scripts/build_showcase_plan.sh"
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
    log "planned stages: preflight -> intel -> thesis -> preview -> adopt -> run -> report -> learn_preview -> learn_adopt"
  fi
}

stage_intel() {
  STAGES_RUN+=("intel")
  log "stage=intel"
  run_best_effort bash "$CONTROL_DIR/scripts/research_refresh.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/idea_shortlist.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_control_tower_digest.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_next_batch_plan.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_showcase_plan.sh"
  log "artifacts: shared-context/SIGNALS.md, idea_bank/shortlist.json, reports/control_tower/*, plans/next_batch_plan.json, reports/showcase/showcase_plan_*.json"
}

stage_thesis() {
  STAGES_RUN+=("thesis")
  log "stage=thesis"
  run_best_effort bash "$CONTROL_DIR/scripts/build_thesis_update_draft.sh" --date "$TODAY"
}

stage_preview() {
  STAGES_RUN+=("preview")
  log "stage=preview"
  # preview artifacts are safe and intentionally generated even in DRY_RUN
  bash "$CONTROL_DIR/scripts/build_thesis_preview.sh" --date "$TODAY" || true
  bash "$CONTROL_DIR/scripts/build_weekly_run_preview.sh" --date "$TODAY" || true
}

stage_adopt() {
  STAGES_RUN+=("adopt")
  log "stage=adopt"
  load_profile
  log "adoption flags: ADOPT_THESIS_DRAFT=${ADOPT_THESIS_DRAFT}, ADOPT_WEEKLY_RUN=${ADOPT_WEEKLY_RUN}"

  if [ "$DRY_RUN" = "1" ]; then
    if [ "$ADOPT_THESIS_DRAFT" = "1" ]; then
      log "DRY-RUN: would run adopt_thesis_draft.sh (ADOPT_THESIS_DRAFT=1)"
    else
      log "DRY-RUN: skip thesis adoption (ADOPT_THESIS_DRAFT=0)"
    fi
    if [ "$ADOPT_WEEKLY_RUN" = "1" ]; then
      log "DRY-RUN: would run adopt_weekly_run.sh (ADOPT_WEEKLY_RUN=1)"
    else
      log "DRY-RUN: skip weekly_run adoption (ADOPT_WEEKLY_RUN=0)"
    fi
    return 0
  fi

  if [ "$ADOPT_THESIS_DRAFT" = "1" ]; then
    ADOPT_THESIS_DRAFT=1 bash "$CONTROL_DIR/scripts/adopt_thesis_draft.sh" --date "$TODAY" || true
  else
    log "thesis adoption skipped by profile"
  fi

  if [ "$ADOPT_WEEKLY_RUN" = "1" ]; then
    ADOPT_WEEKLY_RUN=1 bash "$CONTROL_DIR/scripts/adopt_weekly_run.sh" --date "$TODAY" || true
  else
    log "weekly_run adoption skipped by profile"
  fi
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
  run_best_effort bash "$CONTROL_DIR/scripts/evaluate_portfolio.sh"

  local stages_csv
  stages_csv=$(IFS=,; echo "${STAGES_RUN[*]}")
  local flags_json
  flags_json=$(jq -nc \
    --arg u "$USE_NEXT_BATCH_PLAN" \
    --arg c "$ADOPT_NEXT_BATCH_COMPLEXITY" \
    --arg s "$ADOPT_NEXT_BATCH_COMPONENTS" \
    --arg e "$ADOPT_NEXT_BATCH_ENHANCEMENT" \
    --arg t "$ADOPT_THESIS_DRAFT" \
    --arg w "$ADOPT_WEEKLY_RUN" \
    --arg m "$ADOPT_MEMORY_UPDATES" \
    --arg f "$ADOPT_FEEDBACK_UPDATES" \
    --arg n "$ADOPT_SOURCE_NOTES" \
    --arg r "$ADOPT_LEARNED_RULES" \
    '{USE_NEXT_BATCH_PLAN:$u,ADOPT_NEXT_BATCH_COMPLEXITY:$c,ADOPT_NEXT_BATCH_COMPONENTS:$s,ADOPT_NEXT_BATCH_ENHANCEMENT:$e,ADOPT_THESIS_DRAFT:$t,ADOPT_WEEKLY_RUN:$w,ADOPT_MEMORY_UPDATES:$m,ADOPT_FEEDBACK_UPDATES:$f,ADOPT_SOURCE_NOTES:$n,ADOPT_LEARNED_RULES:$r}')

  run_best_effort bash "$CONTROL_DIR/scripts/build_weekly_run_report.sh" \
    --date "$TODAY" \
    --adoption-profile "$ADOPTION_PROFILE" \
    --dry-run "$DRY_RUN" \
    --stages "$stages_csv" \
    --resume-executed "$RESUME_EXECUTED" \
    --flags-json "$flags_json"
}

stage_learn_preview() {
  STAGES_RUN+=("learn_preview")
  log "stage=learn_preview"
  # learning preview is a read-mostly report and safe to generate
  bash "$CONTROL_DIR/scripts/build_learning_update_preview.sh" --date "$TODAY" || true
}

stage_learn_adopt() {
  STAGES_RUN+=("learn_adopt")
  log "stage=learn_adopt"
  load_profile
  log "learning flags: ADOPT_MEMORY_UPDATES=${ADOPT_MEMORY_UPDATES}, ADOPT_FEEDBACK_UPDATES=${ADOPT_FEEDBACK_UPDATES}, ADOPT_SOURCE_NOTES=${ADOPT_SOURCE_NOTES}, ADOPT_LEARNED_RULES=${ADOPT_LEARNED_RULES}"

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN: memory=${ADOPT_MEMORY_UPDATES} feedback=${ADOPT_FEEDBACK_UPDATES} sources=${ADOPT_SOURCE_NOTES} rules=${ADOPT_LEARNED_RULES}"
    return 0
  fi

  ADOPT_MEMORY_UPDATES="$ADOPT_MEMORY_UPDATES" \
  ADOPT_FEEDBACK_UPDATES="$ADOPT_FEEDBACK_UPDATES" \
  ADOPT_SOURCE_NOTES="$ADOPT_SOURCE_NOTES" \
  ADOPT_LEARNED_RULES="$ADOPT_LEARNED_RULES" \
  bash "$CONTROL_DIR/scripts/adopt_learning_updates.sh" --date "$TODAY" || true
}

load_profile

case "$STAGE" in
  all)
    stage_preflight
    stage_intel
    stage_thesis
    stage_preview
    stage_adopt
    stage_run
    stage_report
    stage_learn_preview
    stage_learn_adopt
    ;;
  preflight) stage_preflight ;;
  intel) stage_intel ;;
  thesis) stage_thesis ;;
  preview) stage_preview ;;
  adopt) stage_adopt ;;
  run) stage_run ;;
  report) stage_report ;;
  learn_preview) stage_learn_preview ;;
  learn_adopt) stage_learn_adopt ;;
  *)
    echo "Unknown STAGE=$STAGE (expected: all|preflight|intel|thesis|preview|adopt|run|report|learn_preview|learn_adopt)" >&2
    exit 1
    ;;
esac

log "done"
