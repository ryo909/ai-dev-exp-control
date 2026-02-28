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

START_DAY=${1:?'Usage: run_batch.sh <start_day> <batch_size>'}
BATCH_SIZE=${2:-7}
END_DAY=$((START_DAY + BATCH_SIZE - 1))

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  run_batch: Day$(printf '%03d' "$START_DAY") 〜 Day$(printf '%03d' "$END_DAY")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

COMPLETED=0
FAILED=0

load_env_file() {
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
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
          text: ($entry.post_texts.standard // $entry.post_texts.compact // $entry.post_texts.minimal // "")
        }
      | select(.text != "")
    ]
    | sort_by(.day)
    | reverse
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
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "$now" \
     --arg batch_id "$batch_id" \
     --argjson posts "$posts_json" \
     '
     reduce $posts[] as $p (.;
       if .days[$p.day] then .days[$p.day].status = "posted" else . end
     )
     | .post_pending = null
     | .last_make_webhook = {
         batch_id: $batch_id,
         sent_at: $now,
         posted_count: ($posts | length),
         posted_days: ($posts | map(.day))
       }
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
  rm -f "$response_file"

  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  fi
  return 1
}

for i in $(seq 0 $((BATCH_SIZE - 1))); do
  DAY_NUM=$((START_DAY + i))
  DAY_STR=$(printf '%03d' "$DAY_NUM")

  echo ""
  echo "──── Day${DAY_STR} [$((i + 1))/${BATCH_SIZE}] ────"

  if bash "$SCRIPT_DIR/run_day.sh" "$DAY_NUM"; then
    COMPLETED=$((COMPLETED + 1))
    echo "✅ Day${DAY_STR} 完了"
  else
    FAILED=$((FAILED + 1))
    echo "❌ Day${DAY_STR} 失敗 — 後続Dayを続行します"
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

POST_COUNT=$(jq 'length' <<<"$POSTS_JSON")
if [ "$POST_COUNT" -eq 0 ]; then
  echo "⚠ 送信対象postがありません。Make送信をスキップします。"
else
  if [ -z "$MAKE_WEBHOOK_URL" ] || [ -z "$MAKE_WEBHOOK_APIKEY" ]; then
    echo "❌ MAKE_WEBHOOK_URL / MAKE_WEBHOOK_APIKEY が未設定です。"
    save_post_pending "$BATCH_ID" "$POSTS_JSON" "missing_make_webhook_env"
    echo "→ post_pending に未送信${POST_COUNT}件を保存して停止します。"
    exit 1
  fi

  echo "▶ Make Webhookへ${POST_COUNT}件を送信します（逆順）。"
  if push_make_webhook "$BATCH_ID" "$POSTS_JSON"; then
    mark_posts_as_posted "$BATCH_ID" "$POSTS_JSON"
    echo "✅ Make Webhook送信成功: ${POST_COUNT}件"
  else
    save_post_pending "$BATCH_ID" "$POSTS_JSON" "make_webhook_request_failed"
    echo "❌ Make Webhook送信失敗。post_pending に未送信${POST_COUNT}件を保存して停止します。"
    exit 1
  fi
fi

# ---- カタログ更新 ----
echo ""
echo "▶ カタログを更新..."
bash "$SCRIPT_DIR/build_catalog.sh"

# ---- last_run 更新 ----
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq ".last_run = \"${NOW}\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# ---- control repo commit & push ----
echo ""
echo "▶ control repo を commit & push..."
cd "$CONTROL_DIR"
git add -A
git commit -m "batch: Day$(printf '%03d' "$START_DAY")-Day$(printf '%03d' $((START_DAY + COMPLETED - 1))) completed" || true
git push origin main || {
  echo "⚠ git push失敗。手動でpushしてください。"
}

echo ""
echo "🏁 バッチ処理完了！"
