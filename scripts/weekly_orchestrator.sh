#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_FILE="$CONTROL_DIR/system/adoption_profiles.json"

DRY_RUN="${DRY_RUN:-0}"
STAGE="${STAGE:-all}"
ADOPTION_PROFILE="${ADOPTION_PROFILE:-safe}"
TODAY="$(date +%F)"
PUBLISH_MODE="${PUBLISH_MODE:-preview}"               # preview | send
ALLOW_EXTERNAL_SEND="${ALLOW_EXTERNAL_SEND:-0}"       # 1 when send is explicitly allowed
PUBLISH_PLATFORMS="${PUBLISH_PLATFORMS:-x,youtube}"   # csv
PUBLISH_APPLY_GALLERY="${PUBLISH_APPLY_GALLERY:-1}"   # 1 to apply gallery in weekly flow
PUBLISH_DAYS="${PUBLISH_DAYS:-}"                      # override day csv (e.g. 009,010)
PUBLISH_FORCE="${PUBLISH_FORCE:-0}"                   # pass --force to send_make_payload.sh when needed
PUBLISH_BATCH_ID_PREFIX="${PUBLISH_BATCH_ID_PREFIX:-weekly}"

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
RUN_DAY_CSV=""
LAST_PUBLISH_SUMMARY_FILE=""

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

rel_path() {
  local p="${1:-}"
  if [ -z "$p" ]; then
    echo ""
    return 0
  fi
  echo "${p#$CONTROL_DIR/}"
}

latest_file() {
  local pattern="$1"
  local f
  f=$(ls -1t $pattern 2>/dev/null | head -n 1 || true)
  echo "$f"
}

normalize_days_csv() {
  local raw="${1:-}"
  jq -nr --arg csv "$raw" '
    ($csv
     | split(",")
     | map(gsub("[^0-9]"; ""))
     | map(select(length > 0))
     | map((. | tonumber) as $n | ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end)
    ) | unique | sort | join(",")
  '
}

range_days_csv() {
  local start="$1"
  local end="$2"
  jq -nr --argjson s "$start" --argjson e "$end" '
    [ range($s; ($e + 1))
      | tostring
      | if length==1 then "00"+. elif length==2 then "0"+. else . end
    ] | join(",")
  '
}

resolve_publish_days_csv() {
  if [ -n "$PUBLISH_DAYS" ]; then
    normalize_days_csv "$PUBLISH_DAYS"
    return 0
  fi
  if [ -n "$RUN_DAY_CSV" ]; then
    normalize_days_csv "$RUN_DAY_CSV"
    return 0
  fi
  local mp="$CONTROL_DIR/exports/launch/make_payload_${TODAY}.json"
  if [ -f "$mp" ]; then
    jq -r '
      [
        ((.x_items // .publish_items // [])[]? | .day),
        ((.youtube_items // [])[]? | .day)
      ]
      | map(tostring)
      | map(gsub("[^0-9]"; ""))
      | map(select(length > 0))
      | map((. | tonumber) as $n | ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end)
      | unique
      | sort
      | join(",")
    ' "$mp"
    return 0
  fi
  echo ""
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
    "$CONTROL_DIR/scripts/build_growth_brief.sh"
    "$CONTROL_DIR/scripts/build_strategy_brief.sh"
    "$CONTROL_DIR/scripts/build_evidence_report.sh"
    "$CONTROL_DIR/scripts/build_reality_gate.sh"
    "$CONTROL_DIR/scripts/build_launch_pack.sh"
    "$CONTROL_DIR/scripts/build_launch_exports.sh"
    "$CONTROL_DIR/scripts/apply_gallery_entries.sh"
    "$CONTROL_DIR/scripts/send_make_payload.sh"
    "$CONTROL_DIR/scripts/build_healthcheck_report.sh"
    "$CONTROL_DIR/scripts/collect_post_launch_feedback.sh"
    "$CONTROL_DIR/scripts/build_post_launch_feedback_digest.sh"
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
  run_best_effort bash "$CONTROL_DIR/scripts/build_healthcheck_report.sh" --date "$TODAY"
  if [ -f "$CONTROL_DIR/reports/healthcheck/healthcheck_${TODAY}.json" ]; then
    local hstatus
    hstatus=$(jq -r '.summary.overall_status // "n/a"' "$CONTROL_DIR/reports/healthcheck/healthcheck_${TODAY}.json" 2>/dev/null || echo "n/a")
    log "healthcheck overall_status=${hstatus}"
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "planned stages: preflight -> intel -> thesis -> preview -> adopt -> run -> publish -> report -> learn_preview -> learn_adopt"
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

  local next_day target_day batch_size actual_batch run_end_day
  next_day=$(jq -r '.next_day // 1' "$CONTROL_DIR/STATE.json" 2>/dev/null || echo "1")
  target_day=$(jq -r '.target_day // 1' "$CONTROL_DIR/STATE.json" 2>/dev/null || echo "1")
  batch_size=$(jq -r '.batch_size_default // 7' "$CONTROL_DIR/STATE.json" 2>/dev/null || echo "7")
  actual_batch="$batch_size"
  if [ "$next_day" -gt "$target_day" ]; then
    RUN_DAY_CSV=""
  else
    local remaining
    remaining=$((target_day - next_day + 1))
    if [ "$remaining" -lt "$batch_size" ]; then
      actual_batch="$remaining"
    fi
    run_end_day=$((next_day + actual_batch - 1))
    RUN_DAY_CSV=$(range_days_csv "$next_day" "$run_end_day")
  fi
  log "run target days: ${RUN_DAY_CSV:-none}"

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
  run_best_effort bash "$CONTROL_DIR/scripts/build_growth_brief.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_strategy_brief.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_evidence_report.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_reality_gate.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_launch_pack.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_launch_exports.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/collect_post_launch_feedback.sh"
  run_best_effort bash "$CONTROL_DIR/scripts/build_post_launch_feedback_digest.sh"

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
    --publish-mode "$PUBLISH_MODE" \
    --allow-external-send "$ALLOW_EXTERNAL_SEND" \
    --publish-summary "$LAST_PUBLISH_SUMMARY_FILE" \
    --flags-json "$flags_json"
}

stage_publish() {
  STAGES_RUN+=("publish")
  log "stage=publish"
  log "publish config: mode=${PUBLISH_MODE} allow_external_send=${ALLOW_EXTERNAL_SEND} platforms=${PUBLISH_PLATFORMS} apply_gallery=${PUBLISH_APPLY_GALLERY} force=${PUBLISH_FORCE}"

  local day_csv
  day_csv=$(resolve_publish_days_csv)
  if [ -z "$day_csv" ]; then
    log "publish skipped: target days unresolved (set PUBLISH_DAYS to override)"
    LAST_PUBLISH_SUMMARY_FILE=""
    return 0
  fi
  log "publish target days=${day_csv}"

  local platforms_json
  platforms_json=$(jq -nc --arg csv "$PUBLISH_PLATFORMS" '
    ($csv
     | ascii_downcase
     | split(",")
     | map(gsub("[^a-z]"; ""))
     | map(select(length > 0))
     | map(if . == "twitter" then "x" else . end)
     | map(select(. == "x" or . == "youtube"))
    ) | unique | sort
  ')
  if [ "$(jq 'length' <<<"$platforms_json")" -eq 0 ]; then
    log "publish skipped: target platforms empty (PUBLISH_PLATFORMS=${PUBLISH_PLATFORMS})"
    LAST_PUBLISH_SUMMARY_FILE=""
    return 0
  fi

  local report_dir="$CONTROL_DIR/reports/publish"
  mkdir -p "$report_dir"
  local gallery_report="$report_dir/gallery_apply_${TODAY}.json"
  local combined_preview_report=""
  local x_preview_report=""
  local y_preview_report=""
  local x_send_report=""
  local y_send_report=""
  local send_requested="false"
  local send_executed="false"

  run_best_effort bash "$CONTROL_DIR/scripts/build_launch_exports.sh" --date "$TODAY" --days "$day_csv"

  local before after
  before=$(latest_file "$report_dir/publish_preview_*.json")
  run_best_effort bash "$CONTROL_DIR/scripts/send_make_payload.sh" --date "$TODAY" --days "$day_csv" --webhook-only --preview --platforms x,youtube
  after=$(latest_file "$report_dir/publish_preview_*.json")
  [ -n "$after" ] && combined_preview_report="$after"
  [ "$after" = "$before" ] && log "publish preview (x,youtube): no new report detected"

  before=$(latest_file "$report_dir/publish_preview_*.json")
  run_best_effort bash "$CONTROL_DIR/scripts/send_make_payload.sh" --date "$TODAY" --days "$day_csv" --webhook-only --preview --platforms x
  after=$(latest_file "$report_dir/publish_preview_*.json")
  [ -n "$after" ] && x_preview_report="$after"

  before=$(latest_file "$report_dir/publish_preview_*.json")
  run_best_effort bash "$CONTROL_DIR/scripts/send_make_payload.sh" --date "$TODAY" --days "$day_csv" --webhook-only --preview --platforms youtube
  after=$(latest_file "$report_dir/publish_preview_*.json")
  [ -n "$after" ] && y_preview_report="$after"

  if [ "$PUBLISH_APPLY_GALLERY" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      run_best_effort bash "$CONTROL_DIR/scripts/apply_gallery_entries.sh" --date "$TODAY" --days "$day_csv" --preview --report-file "$gallery_report"
    else
      run_best_effort bash "$CONTROL_DIR/scripts/apply_gallery_entries.sh" --date "$TODAY" --days "$day_csv" --report-file "$gallery_report"
    fi
  else
    log "gallery apply skipped by flag (PUBLISH_APPLY_GALLERY=0)"
  fi

  if [ "$PUBLISH_MODE" = "send" ]; then
    send_requested="true"
  fi

  if [ "$PUBLISH_MODE" = "send" ] && [ "$ALLOW_EXTERNAL_SEND" = "1" ] && [ "$DRY_RUN" != "1" ]; then
    send_executed="true"
    local common_args=(--date "$TODAY" --days "$day_csv" --webhook-only)
    if [ "$PUBLISH_FORCE" = "1" ]; then
      common_args+=(--force)
    fi
    if jq -e 'index("x")' >/dev/null <<<"$platforms_json"; then
      before=$(latest_file "$report_dir/make_webhook_send_*.json")
      if bash "$CONTROL_DIR/scripts/send_make_payload.sh" "${common_args[@]}" --platforms x --batch-id "${PUBLISH_BATCH_ID_PREFIX}-${TODAY}-x"; then
        :
      else
        log "publish send(x) failed"
      fi
      after=$(latest_file "$report_dir/make_webhook_send_*.json")
      if [ -n "$after" ] && [ "$after" != "$before" ]; then
        x_send_report="$after"
      fi
    fi
    if jq -e 'index("youtube")' >/dev/null <<<"$platforms_json"; then
      before=$(latest_file "$report_dir/make_webhook_send_*.json")
      if bash "$CONTROL_DIR/scripts/send_make_payload.sh" "${common_args[@]}" --platforms youtube --batch-id "${PUBLISH_BATCH_ID_PREFIX}-${TODAY}-youtube"; then
        :
      else
        log "publish send(youtube) failed"
      fi
      after=$(latest_file "$report_dir/make_webhook_send_*.json")
      if [ -n "$after" ] && [ "$after" != "$before" ]; then
        y_send_report="$after"
      fi
    fi
  elif [ "$PUBLISH_MODE" = "send" ] && [ "$ALLOW_EXTERNAL_SEND" != "1" ]; then
    log "publish send requested but blocked: set ALLOW_EXTERNAL_SEND=1 to enable external send"
  fi

  local target_days_json
  target_days_json=$(jq -nc --arg csv "$day_csv" '
    ($csv | split(",") | map(select(length>0))) | unique | sort
  ')
  local combined_preview_json x_preview_json y_preview_json gallery_json x_send_json y_send_json
  combined_preview_json=$( [ -n "$combined_preview_report" ] && [ -f "$combined_preview_report" ] && cat "$combined_preview_report" || echo '{}' )
  x_preview_json=$( [ -n "$x_preview_report" ] && [ -f "$x_preview_report" ] && cat "$x_preview_report" || echo '{}' )
  y_preview_json=$( [ -n "$y_preview_report" ] && [ -f "$y_preview_report" ] && cat "$y_preview_report" || echo '{}' )
  gallery_json=$( [ -f "$gallery_report" ] && cat "$gallery_report" || echo '{}' )
  x_send_json=$( [ -n "$x_send_report" ] && [ -f "$x_send_report" ] && cat "$x_send_report" || echo '{}' )
  y_send_json=$( [ -n "$y_send_report" ] && [ -f "$y_send_report" ] && cat "$y_send_report" || echo '{}' )

  LAST_PUBLISH_SUMMARY_FILE="$report_dir/publish_weekly_summary_${TODAY}.json"
  jq -nc \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg date "$TODAY" \
    --arg dry_run "$DRY_RUN" \
    --arg publish_mode "$PUBLISH_MODE" \
    --arg allow_external_send "$ALLOW_EXTERNAL_SEND" \
    --arg send_requested "$send_requested" \
    --arg send_executed "$send_executed" \
    --argjson target_days "$target_days_json" \
    --argjson target_platforms "$platforms_json" \
    --arg combined_preview_path "$(rel_path "$combined_preview_report")" \
    --arg x_preview_path "$(rel_path "$x_preview_report")" \
    --arg youtube_preview_path "$(rel_path "$y_preview_report")" \
    --arg gallery_report_path "$(rel_path "$gallery_report")" \
    --arg x_send_report_path "$(rel_path "$x_send_report")" \
    --arg youtube_send_report_path "$(rel_path "$y_send_report")" \
    --argjson combined_preview "$combined_preview_json" \
    --argjson x_preview "$x_preview_json" \
    --argjson youtube_preview "$y_preview_json" \
    --argjson gallery "$gallery_json" \
    --argjson x_send "$x_send_json" \
    --argjson youtube_send "$y_send_json" \
    '
    def sent_targets_from($r):
      if (($r.sent_targets // null) | type) == "array" then ($r.sent_targets // [])
      elif (($r.sent_posts // null) | type) == "array" then
        [($r.sent_posts // [])[] | {day: (.day|tostring), platform: ((.platform // "x")|ascii_downcase), key: ((.day|tostring) + "-" + ((.platform // "x")|ascii_downcase))}]
      else [] end;
    def blocked_targets_from_preview($p):
      if (($p.youtube_preview // null) | type) == "array" then
        [($p.youtube_preview // [])[]
         | select((.readiness // "ready") != "ready")
         | {day: (.day|tostring), platform: "youtube", key: ((.day|tostring) + "-youtube"), readiness: (.readiness // ""), missing_fields: (.missing_fields // [])}]
      else [] end;
    (sent_targets_from($x_send)) as $x_sent_targets
    | (sent_targets_from($youtube_send)) as $youtube_sent_targets
    | (($combined_preview.overlap_targets // []) | map({day: (.day|tostring), platform: ((.platform // "x")|ascii_downcase), key: (.key // ((.day|tostring) + "-" + ((.platform // "x")|ascii_downcase)))}) ) as $duplicate_targets
    | (blocked_targets_from_preview($combined_preview)) as $blocked_targets
    | ($duplicate_targets + ($blocked_targets | map({day, platform, key}))) as $skipped_targets
    | (($x_sent_targets + $youtube_sent_targets) | map(.batch_id // empty) | map(select(length > 0)) | unique) as $batch_ids
    | {
        generated_at: $generated_at,
        date: $date,
        dry_run: ($dry_run == "1"),
        publish_mode: $publish_mode,
        allow_external_send: ($allow_external_send == "1"),
        external_send_requested: ($send_requested == "true"),
        external_send_executed: ($send_executed == "true"),
        target_days: $target_days,
        target_platforms: $target_platforms,
        target_count: (($target_days | length) * ($target_platforms | length)),
        reports: {
          combined_preview: $combined_preview_path,
          x_preview: $x_preview_path,
          youtube_preview: $youtube_preview_path,
          gallery_apply: $gallery_report_path,
          x_send: $x_send_report_path,
          youtube_send: $youtube_send_report_path
        },
        readiness: {
          x_ready_count: ($combined_preview.x_ready_count // 0),
          youtube_ready_count: ($combined_preview.youtube_ready_count // 0),
          youtube_pending_asset_count: ($combined_preview.youtube_pending_asset_count // 0),
          youtube_blocked_count: ($combined_preview.youtube_blocked_count // 0),
          youtube_invalid_count: ($combined_preview.youtube_invalid_count // 0),
          youtube_missing_video_count: ($combined_preview.youtube_missing_video_count // 0)
        },
        gallery_apply_count: ($gallery.selected_count // ($gallery.summary.selected_count // 0)),
        dueAt_summary: ($combined_preview.dueAt_summary // {}),
        duplicate_targets: $duplicate_targets,
        duplicate_target_count: ($duplicate_targets | length),
        blocked_targets: $blocked_targets,
        blocked_target_count: ($blocked_targets | length),
        skipped_targets: ($skipped_targets | unique_by(.key)),
        skipped_target_count: (($skipped_targets | unique_by(.key)) | length),
        x_sent_targets: ($x_sent_targets | map(select((.platform // "") == "x"))),
        youtube_sent_targets: ($youtube_sent_targets | map(select((.platform // "") == "youtube"))),
        sent_target_count: ((($x_sent_targets + $youtube_sent_targets) | unique_by(.key)) | length),
        batch_ids: (
          [
            ($x_send.batch_id // empty),
            ($youtube_send.batch_id // empty)
          ] + $batch_ids
          | map(select(length > 0))
          | unique
        ),
        notes: [
          (if $publish_mode == "preview" then "safe mode: preview only, no external send" else empty end),
          (if ($publish_mode == "send" and ($allow_external_send != "1")) then "send requested but blocked by guard: ALLOW_EXTERNAL_SEND=1 is required" else empty end)
        ] | map(select(length > 0))
      }' > "$LAST_PUBLISH_SUMMARY_FILE"

  local summary_md="$report_dir/publish_weekly_summary_${TODAY}.md"
  {
    echo "# Publish Weekly Summary (${TODAY})"
    echo ""
    echo "- publish_mode: ${PUBLISH_MODE}"
    echo "- allow_external_send: ${ALLOW_EXTERNAL_SEND}"
    echo "- external_send_executed: ${send_executed}"
    echo "- target_days: ${day_csv}"
    echo "- target_platforms: ${PUBLISH_PLATFORMS}"
    echo "- summary_json: $(rel_path "$LAST_PUBLISH_SUMMARY_FILE")"
  } > "$summary_md"
  log "publish summary: $(rel_path "$LAST_PUBLISH_SUMMARY_FILE")"
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
    stage_publish
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
  publish) stage_publish ;;
  learn_preview) stage_learn_preview ;;
  learn_adopt) stage_learn_adopt ;;
  *)
    echo "Unknown STAGE=$STAGE (expected: all|preflight|intel|thesis|preview|adopt|run|report|publish|learn_preview|learn_adopt)" >&2
    exit 1
    ;;
esac

log "done"
