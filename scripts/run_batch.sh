#!/usr/bin/env bash
# ============================================================
# run_batch.sh — バッチ処理（7本分）
# Usage: run_batch.sh <start_day_number> <batch_size>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"

START_DAY=${1:?'Usage: run_batch.sh <start_day> <batch_size>'}
BATCH_SIZE=${2:-7}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  run_batch: Day$(printf '%03d' "$START_DAY") 〜 Day$(printf '%03d' $((START_DAY + BATCH_SIZE - 1)))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

COMPLETED=0
FAILED=0

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

# ---- Buffer投入（7本分） ----
echo ""
echo "▶ Buffer投入チェック..."

BUFFER_TOKEN="${BUFFER_ACCESS_TOKEN:-}"
if [ -z "$BUFFER_TOKEN" ]; then
  echo "⚠ BUFFER_ACCESS_TOKEN が設定されていません。"
  echo "  → 投稿予約はスキップされました。手動でBuffer投入してください。"
  echo "  → 各DayのSTATEに post_texts が記録されています。"
else
  echo "▶ Buffer投入を開始..."
  # Buffer Profile ID を取得
  PROFILE_ID=$(curl -s "https://api.bufferapp.com/1/profiles.json?access_token=${BUFFER_TOKEN}" | jq -r '.[0].id // empty')

  if [ -z "$PROFILE_ID" ]; then
    echo "❌ BufferプロファイルIDの取得に失敗しました。"
    echo "  → BUFFER_ACCESS_TOKENを確認してください。投稿予約はスキップします。"
  else
    POSTED=0
    for i in $(seq 0 $((BATCH_SIZE - 1))); do
      DAY_NUM=$((START_DAY + i))
      DAY_STR=$(printf '%03d' "$DAY_NUM")

      # STATEからpost_textを取得
      STATUS=$(jq -r ".days[\"${DAY_STR}\"].status // empty" "$STATE_FILE")
      if [ "$STATUS" != "done" ] && [ "$STATUS" != "deployed" ]; then
        continue
      fi

      # 標準→圧縮→最小の順で投入試行
      for VARIANT in standard compact minimal; do
        POST_TEXT=$(jq -r ".days[\"${DAY_STR}\"].post_texts.${VARIANT} // empty" "$STATE_FILE")
        if [ -z "$POST_TEXT" ]; then continue; fi

        RESPONSE=$(curl -s -X POST "https://api.bufferapp.com/1/updates/create.json" \
          --data-urlencode "access_token=${BUFFER_TOKEN}" \
          --data-urlencode "profile_ids[]=${PROFILE_ID}" \
          --data-urlencode "text=${POST_TEXT}" \
          --data-urlencode "top=false")

        SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false')
        if [ "$SUCCESS" = "true" ]; then
          echo "  ✅ Day${DAY_STR} Buffer投入成功（${VARIANT}）"
          # STATEのstatusを更新
          jq ".days[\"${DAY_STR}\"].status = \"posted\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
          POSTED=$((POSTED + 1))
          break
        else
          echo "  ⚠ Day${DAY_STR} Buffer投入失敗（${VARIANT}）: $(echo "$RESPONSE" | jq -r '.message // "unknown error"')"
          if [ "$VARIANT" = "minimal" ]; then
            echo "  ❌ Day${DAY_STR}: 全テンプレート失敗。停止して報告。"
            echo "  → 手動でBuffer投入してください。post_textsはSTATEに記録済みです。"
          fi
        fi
      done
    done
    echo "  Buffer投入完了: ${POSTED}本"
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
