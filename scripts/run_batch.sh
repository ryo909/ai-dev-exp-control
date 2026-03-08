#!/usr/bin/env bash
# ============================================================
# run_batch.sh — バッチ処理（7本分）
# Usage: run_batch.sh <start_day_number> <batch_size>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"
ENV_FILE="$CONTROL_DIR/.env.local"
LOG_DIR="$CONTROL_DIR/logs"
SCHEDULE_POLICY_FILE="$CONTROL_DIR/system/publish_schedule_policy.json"

START_DAY=${1:?'Usage: run_batch.sh <start_day> <batch_size>'}
BATCH_SIZE=${2:-7}
END_DAY=$((START_DAY + BATCH_SIZE - 1))

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  run_batch: Day$(printf '%03d' "$START_DAY") 〜 Day$(printf '%03d' "$END_DAY")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$LOG_DIR"

COMPLETED=0
FAILED=0
WEBHOOK_RESPONSE_BODY=""
WEBHOOK_SCHEDULE_PREVIEW="[]"
SCHEDULE_TIME="21:00"
SCHEDULE_START_OFFSET_DAYS="1"
SCHEDULE_BASE_DATE="$(TZ=Asia/Tokyo date +%Y-%m-%d)"
SCHEDULE_TIMEZONE="Asia/Tokyo"

write_failure_summary() {
  local day_str="$1"
  local log_file="$2"
  local summary_file="$LOG_DIR/Day${day_str}.summary.md"
  {
    echo "# Day${day_str} failure summary"
    echo ""
    echo "generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "## Error-like lines"
    grep -Ein "error|failed|❌|traceback|exception" "$log_file" | tail -n 120 || true
    echo ""
    echo "## Log tail (last 120 lines)"
    tail -n 120 "$log_file" || true
  } > "$summary_file"
}

load_env_file() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  local policy_start_offset="1"
  local policy_timezone="Asia/Tokyo"
  if [ -f "$SCHEDULE_POLICY_FILE" ]; then
    policy_start_offset=$(jq -r '.start_offset_days // 1' "$SCHEDULE_POLICY_FILE" 2>/dev/null || echo "1")
    policy_timezone=$(jq -r '.timezone // "Asia/Tokyo"' "$SCHEDULE_POLICY_FILE" 2>/dev/null || echo "Asia/Tokyo")
  fi
  SCHEDULE_TIME="${MAKE_SCHEDULE_TIME:-21:00}"
  SCHEDULE_START_OFFSET_DAYS="${MAKE_SCHEDULE_START_OFFSET_DAYS:-$policy_start_offset}"
  SCHEDULE_BASE_DATE="${MAKE_SCHEDULE_BASE_DATE:-$(TZ="$policy_timezone" date +%Y-%m-%d)}"
  SCHEDULE_TIMEZONE="${MAKE_SCHEDULE_TIMEZONE:-$policy_timezone}"
  if [[ ! "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "❌ invalid MAKE_SCHEDULE_TIME (expected HH:MM): $SCHEDULE_TIME" >&2
    exit 1
  fi
  if [[ ! "$SCHEDULE_START_OFFSET_DAYS" =~ ^-?[0-9]+$ ]]; then
    echo "❌ invalid MAKE_SCHEDULE_START_OFFSET_DAYS: $SCHEDULE_START_OFFSET_DAYS" >&2
    exit 1
  fi
}

weekday_key_for_date() {
  local target_date="$1"
  local dow
  dow=$(TZ="$SCHEDULE_TIMEZONE" date -d "$target_date" +%u)
  case "$dow" in
    1) echo "mon" ;;
    2) echo "tue" ;;
    3) echo "wed" ;;
    4) echo "thu" ;;
    5) echo "fri" ;;
    6) echo "sat" ;;
    7) echo "sun" ;;
    *) echo "mon" ;;
  esac
}

resolve_schedule_time() {
  local platform="$1"
  local target_date="$2"
  local fallback="$3"
  local wk
  wk=$(weekday_key_for_date "$target_date")
  local slot=""
  if [ -f "$SCHEDULE_POLICY_FILE" ]; then
    slot=$(jq -r --arg p "$platform" --arg wk "$wk" '.platforms[$p].weekly_slots[$wk] // empty' "$SCHEDULE_POLICY_FILE" 2>/dev/null || true)
  fi
  if [[ "$slot" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "$slot"
    return 0
  fi
  if [[ "$fallback" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "$fallback"
    return 0
  fi
  echo "21:00"
}

build_due_at() {
  local base_date="$1"
  local idx="$2"
  local platform="$3"
  local start_offset="$4"
  local fallback="$5"
  local target_date
  target_date=$(TZ="$SCHEDULE_TIMEZONE" date -d "${base_date} +${start_offset} day +${idx} day" +"%Y-%m-%d")
  local hhmm
  hhmm=$(resolve_schedule_time "$platform" "$target_date" "$fallback")
  TZ="$SCHEDULE_TIMEZONE" date -d "${target_date} ${hhmm}:00" +"%Y-%m-%dT%H:%M:%S%:z"
}

normalize_posts_for_webhook() {
  local posts_json="$1"
  local tmp_file
  local x_idx
  local y_idx
  tmp_file=$(mktemp)
  x_idx=0
  y_idx=0

  while IFS= read -r row; do
    [ -z "$row" ] && continue
    platform=$(jq -r '(.platform // "x") | ascii_downcase' <<<"$row")
    day=$(jq -r '(.day // "" | tostring | gsub("[^0-9]"; "") | if length==1 then "00"+. elif length==2 then "0"+. else . end)' <<<"$row")
    [ -z "$day" ] && continue
    if [ "$platform" = "x" ]; then
      text=$(jq -r '.text // empty' <<<"$row")
      [ -z "$text" ] && continue
      due_at=$(jq -r '.dueAt // empty' <<<"$row")
      if [ -z "$due_at" ]; then
        due_at=$(build_due_at "$SCHEDULE_BASE_DATE" "$x_idx" "x" "$SCHEDULE_START_OFFSET_DAYS" "$SCHEDULE_TIME")
      fi
      jq -nc --arg day "$day" --arg text "$text" --arg dueAt "$due_at" \
        '{day:$day, platform:"x", text:$text, dueAt:$dueAt}' >> "$tmp_file"
      x_idx=$((x_idx + 1))
      continue
    fi

    if [ "$platform" = "youtube" ]; then
      title=$(jq -r '.title // empty' <<<"$row")
      description=$(jq -r '.description // empty' <<<"$row")
      video_url=$(jq -r '.videoUrl // empty' <<<"$row")
      thumb_url=$(jq -r '.thumbnailUrl // empty' <<<"$row")
      due_at=$(jq -r '.dueAt // empty' <<<"$row")
      readiness=$(jq -r '.readiness // empty' <<<"$row")
      privacy=$(jq -r '.privacy // "public"' <<<"$row")
      made_for_kids=$(jq -r '.madeForKids // false' <<<"$row")
      notify_subscribers=$(jq -r '.notifySubscribers // true' <<<"$row")
      [ -z "$title" ] && continue
      [ -z "$video_url" ] && continue
      if [ -n "$readiness" ] && [ "$readiness" != "ready" ]; then
        continue
      fi
      if [ -z "$due_at" ]; then
        due_at=$(build_due_at "$SCHEDULE_BASE_DATE" "$y_idx" "youtube" "$SCHEDULE_START_OFFSET_DAYS" "$SCHEDULE_TIME")
      fi
      jq -nc \
        --arg day "$day" \
        --arg title "$title" \
        --arg description "$description" \
        --arg videoUrl "$video_url" \
        --arg thumbnailUrl "$thumb_url" \
        --arg dueAt "$due_at" \
        --arg privacy "$privacy" \
        --argjson madeForKids "$made_for_kids" \
        --argjson notifySubscribers "$notify_subscribers" \
        '{day:$day, platform:"youtube", title:$title, description:$description, videoUrl:$videoUrl, thumbnailUrl:$thumbnailUrl, dueAt:$dueAt, privacy:$privacy, madeForKids:$madeForKids, notifySubscribers:$notifySubscribers}' >> "$tmp_file"
      y_idx=$((y_idx + 1))
    fi
  done < <(jq -c 'sort_by((.day // ""), (.platform // "x"))[]' <<<"$posts_json")

  jq -cs 'sort_by(.day, .platform)' "$tmp_file"
  rm -f "$tmp_file"
}

collect_posts_json() {
  local start_day="$1"
  local end_day="$2"
  jq -c --argjson start "$start_day" --argjson end "$end_day" '
    def pad3($n):
      ($n | tostring) as $s
      | if ($s | length) == 1 then "00" + $s
        elif ($s | length) == 2 then "0" + $s
        else $s
        end;
    [
      range($start; $end + 1) as $n
      | pad3($n) as $day
      | .days[$day] as $entry
      | select($entry.status == "done" or $entry.status == "deployed")
      | {
          day: $day,
          platform: "x",
          text: ($entry.post_texts.standard // $entry.post_texts.compact // $entry.post_texts.minimal // "")
        }
      | select(.text != "")
    ]
    | sort_by(.day, .platform)
  ' "$STATE_FILE"
}

save_post_pending() {
  local batch_id="$1"
  local posts_json="$2"
  local reason="$3"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "$now" \
     --arg batch_id "$batch_id" \
     --arg reason "$reason" \
     --argjson pending_posts "$posts_json" \
     '
     .post_pending = {
       batch_id: $batch_id,
       reason: $reason,
       created_at: $now,
       pending_posts: $pending_posts
     }
     ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

mark_posts_as_posted() {
  local batch_id="$1"
  local posts_json="$2"
  local response_body="$3"
  local schedule_preview="$4"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "$now" \
     --arg batch_id "$batch_id" \
     --argjson posts "$posts_json" \
     --arg response_body "$response_body" \
     --argjson schedule_preview "$schedule_preview" \
     '
     ($posts | map(.day) | unique) as $posted_days
     | ($posts | map((.platform // "x") | ascii_downcase) | unique) as $target_platforms
     | ($posts | map({day: (.day | tostring), platform: ((.platform // "x") | ascii_downcase), key: ((.day | tostring) + "-" + ((.platform // "x") | ascii_downcase))}) | unique_by(.key) | sort_by(.day, .platform)) as $posted_targets
     | reduce $posts[] as $p (.;
       if .days[$p.day] then .days[$p.day].status = "posted" else . end
     )
     | .post_pending = null
     | .last_make_webhook = {
         batch_id: $batch_id,
         sent_at: $now,
         posted_count: ($posted_days | length),
         posted_days: $posted_days,
         posted_item_count: ($posts | length),
         posted_target_count: ($posted_targets | length),
         posted_targets: $posted_targets,
         posted_target_keys: ($posted_targets | map(.key)),
         target_platforms: $target_platforms,
         schedule_preview: $schedule_preview,
         response_body: ($response_body | .[0:400])
       }
     | .last_run_at = $now
     | .execution_logs = ((.execution_logs // []) + [{
         executed_at: $now,
         phase: "buffer",
         batch_id: $batch_id,
         posted_count: ($posted_days | length),
         posted_days: $posted_days,
         posted_item_count: ($posts | length),
         posted_target_count: ($posted_targets | length),
         posted_targets: $posted_targets,
         target_platforms: $target_platforms,
         schedule_preview: $schedule_preview
       }])
     ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

push_make_webhook() {
  local batch_id="$1"
  local posts_json="$2"
  local payload response_file http_status

  payload=$(jq -nc --arg batch_id "$batch_id" --argjson posts "$posts_json" \
    '{batch_id: $batch_id, posts: $posts}')

  response_file=$(mktemp)
  http_status=$(curl -sS -o "$response_file" -w "%{http_code}" \
    -X POST "$MAKE_WEBHOOK_URL" \
    -H "x-make-apikey: $MAKE_WEBHOOK_APIKEY" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data-binary "$payload" || true)
  WEBHOOK_RESPONSE_BODY=$(cat "$response_file")

  if jq -e . >/dev/null 2>&1 <<<"$WEBHOOK_RESPONSE_BODY"; then
    WEBHOOK_SCHEDULE_PREVIEW=$(jq -c '
      [
        .. | objects
        | (.scheduled_at? // .scheduled_time? // .schedule_at? // .scheduledAt? // empty)
        | select(type == "string")
      ] | unique | .[:3]
    ' <<<"$WEBHOOK_RESPONSE_BODY")
  else
    WEBHOOK_SCHEDULE_PREVIEW="[]"
  fi

  rm -f "$response_file"

  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  fi
  return 1
}

for i in $(seq 0 $((BATCH_SIZE - 1))); do
  DAY_NUM=$((START_DAY + i))
  DAY_STR=$(printf '%03d' "$DAY_NUM")
  LOG_FILE="$LOG_DIR/Day${DAY_STR}.log"

  echo ""
  echo "──── Day${DAY_STR} [$((i + 1))/${BATCH_SIZE}] ────"

  if bash "$SCRIPT_DIR/run_day.sh" "$DAY_NUM" 2>&1 | tee "$LOG_FILE"; then
    COMPLETED=$((COMPLETED + 1))
    bash "$CONTROL_DIR/scripts/log_daily.sh" "$DAY_STR" "success" "" || true
    QUALITY_OUT="$CONTROL_DIR/reports/quality/day${DAY_STR}_quality.json"
    if [ -x "$CONTROL_DIR/scripts/evaluate_build_quality.sh" ]; then
      bash "$CONTROL_DIR/scripts/evaluate_build_quality.sh" --day "$DAY_STR" || true
      [ -f "$QUALITY_OUT" ] && echo "  ℹ quality report: reports/quality/day${DAY_STR}_quality.json"
    fi
    echo "✅ Day${DAY_STR} 完了"
  else
    FAILED=$((FAILED + 1))
    echo "❌ Day${DAY_STR} 失敗 — 後続Dayを続行します"
    write_failure_summary "$DAY_STR" "$LOG_FILE"
    bash "$CONTROL_DIR/scripts/log_daily.sh" "$DAY_STR" "fail" "logs/Day${DAY_STR}.summary.md" || true
    FALLBACK_OUT="$CONTROL_DIR/plans/candidates/day${DAY_STR}_fallback_plan.json"
    if [ -x "$CONTROL_DIR/scripts/write_fallback_plan.sh" ]; then
      bash "$CONTROL_DIR/scripts/write_fallback_plan.sh" \
        --day "$DAY_STR" \
        --summary "$CONTROL_DIR/logs/Day${DAY_STR}.summary.md" || true
      [ -f "$FALLBACK_OUT" ] && echo "  ℹ fallback plan: plans/candidates/day${DAY_STR}_fallback_plan.json"
    fi
    echo ""
    echo "⚠ 失敗詳細:"
    echo "  - 完了済み: ${COMPLETED}本"
    echo "  - 失敗: ${FAILED}本"
    echo "  - 残り: $((BATCH_SIZE - i - 1))本"
    echo "  - 次の一手: Day${DAY_STR}のエラーログを確認し、手動で修正後 resume.sh を再実行"
    echo ""
    # 失敗しても次のDayを試行する（ただし次のDayも依存がある場合は停止すべき）
    # ここでは継続方針を採用し、STATE上で未完了として残す
    continue
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  バッチ結果: 完了=${COMPLETED} / 失敗=${FAILED}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---- Make Webhook投入（7本分） ----
echo ""
echo "▶ Make Webhook投入チェック..."

load_env_file
MAKE_WEBHOOK_URL="${MAKE_WEBHOOK_URL:-}"
MAKE_WEBHOOK_APIKEY="${MAKE_WEBHOOK_APIKEY:-}"

PENDING_COUNT=$(jq -r 'try (.post_pending.pending_posts | length) catch 0' "$STATE_FILE")
if [ "$PENDING_COUNT" -gt 0 ]; then
  BATCH_ID=$(jq -r '.post_pending.batch_id // empty' "$STATE_FILE")
  POSTS_JSON=$(jq -c '.post_pending.pending_posts' "$STATE_FILE")
  if [ -z "$BATCH_ID" ]; then
    BATCH_ID="retry-$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  echo "▶ 前回未送信のpost_pending ${PENDING_COUNT}件を再送します。"
else
  BATCH_ID="batch-$(date -u +%Y%m%dT%H%M%SZ)-Day$(printf '%03d' "$START_DAY")-Day$(printf '%03d' "$END_DAY")"
  POSTS_JSON=$(collect_posts_json "$START_DAY" "$END_DAY")
fi

POSTS_JSON=$(normalize_posts_for_webhook "$POSTS_JSON")
POST_COUNT=$(jq 'length' <<<"$POSTS_JSON")
if [ "$POST_COUNT" -eq 0 ]; then
  echo "⚠ 送信対象postがありません。Make送信をスキップします。"
else
  echo "▶ webhook payload preview:"
  echo "  - target_days: $(jq -r '[.[].day] | unique | join(",")' <<<"$POSTS_JSON")"
  echo "  - target_platforms: $(jq -r '[.[].platform] | unique | join(",")' <<<"$POSTS_JSON")"
  echo "  - first_dueAt: $(jq -r 'first(.[] | select(.platform=="x") | .dueAt) // ""' <<<"$POSTS_JSON")"
  echo "  - schedule_timezone: $SCHEDULE_TIMEZONE"
  echo "  - schedule_policy_file: $( [ -f "$SCHEDULE_POLICY_FILE" ] && echo "${SCHEDULE_POLICY_FILE#$CONTROL_DIR/}" || echo "none" )"
  if [ -z "$MAKE_WEBHOOK_URL" ] || [ -z "$MAKE_WEBHOOK_APIKEY" ]; then
    echo "❌ MAKE_WEBHOOK_URL / MAKE_WEBHOOK_APIKEY が未設定です。"
    save_post_pending "$BATCH_ID" "$POSTS_JSON" "missing_make_webhook_env"
    echo "→ post_pending に未送信${POST_COUNT}件を保存して停止します。"
    exit 1
  fi

  echo "▶ Make Webhookへ${POST_COUNT}件を送信します。"
  if push_make_webhook "$BATCH_ID" "$POSTS_JSON"; then
    mark_posts_as_posted "$BATCH_ID" "$POSTS_JSON" "$WEBHOOK_RESPONSE_BODY" "$WEBHOOK_SCHEDULE_PREVIEW"
    echo "✅ Make Webhook送信成功: ${POST_COUNT}件"
  else
    save_post_pending "$BATCH_ID" "$POSTS_JSON" "make_webhook_request_failed"
    echo "❌ Make Webhook送信失敗。post_pending に未送信${POST_COUNT}件を保存して停止します。"
    exit 1
  fi
fi

# ---- カタログ更新 ----
echo ""
echo "▶ coverageレポートを更新..."
bash "$SCRIPT_DIR/report_coverage.sh" || true

echo ""
echo "▶ カタログを更新..."
bash "$SCRIPT_DIR/build_catalog.sh"

echo ""
echo "▶ STATE schema検証..."
bash "$SCRIPT_DIR/validate_json.sh" "$CONTROL_DIR/schemas/state_schema.json" "$STATE_FILE"

# ---- last_run 更新 ----
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq ".last_run = \"${NOW}\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# ---- control repo commit & push ----
echo ""
echo "▶ control repo を commit & push..."
cd "$CONTROL_DIR"
CONTROL_PUSH_BRANCH="${CONTROL_PUSH_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"
[ -n "$CONTROL_PUSH_BRANCH" ] || CONTROL_PUSH_BRANCH="main"
git add -A
git commit -m "batch: Day$(printf '%03d' "$START_DAY")-Day$(printf '%03d' $((START_DAY + COMPLETED - 1))) completed" || true
git -c credential.helper=store push origin "$CONTROL_PUSH_BRANCH" || {
  echo "⚠ git push失敗（branch=${CONTROL_PUSH_BRANCH}）。手動でpushしてください。"
}

echo ""
echo "🏁 バッチ処理完了！"
