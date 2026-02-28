#!/usr/bin/env bash
# ============================================================
# resume.sh — 実行入口
# STATEを読み、next_dayと残りを確認し、run_batch.shを呼ぶ
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"

# ---- 依存チェック ----
for cmd in jq gh node npm; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ ERROR: '$cmd' が見つかりません。README.md の必須ツールを確認してください。"
    exit 1
  fi
done

# ---- STATE読み込み ----
if [ ! -f "$STATE_FILE" ]; then
  echo "❌ ERROR: STATE.json が見つかりません: $STATE_FILE"
  exit 1
fi

NEXT_DAY=$(jq -r '.next_day' "$STATE_FILE")
TARGET_DAY=$(jq -r '.target_day' "$STATE_FILE")
BATCH_SIZE=$(jq -r '.batch_size_default' "$STATE_FILE")

echo "=========================================="
echo "  AI個人開発実験 — resume"
echo "=========================================="
echo "  次のDay:     Day$(printf '%03d' "$NEXT_DAY")"
echo "  目標:        Day$(printf '%03d' "$TARGET_DAY")"
echo "  バッチサイズ: $BATCH_SIZE"
echo "=========================================="

# ---- 完了チェック ----
if [ "$NEXT_DAY" -gt "$TARGET_DAY" ]; then
  echo "🎉 全${TARGET_DAY}本が完了しています！おめでとうございます！"
  exit 0
fi

# ---- バッチ実行 ----
REMAINING=$((TARGET_DAY - NEXT_DAY + 1))
ACTUAL_BATCH=$BATCH_SIZE
if [ "$REMAINING" -lt "$BATCH_SIZE" ]; then
  ACTUAL_BATCH=$REMAINING
fi

echo ""
echo "▶ バッチ処理を開始します（${ACTUAL_BATCH}本）..."
echo ""

bash "$SCRIPT_DIR/run_batch.sh" "$NEXT_DAY" "$ACTUAL_BATCH"

echo ""
echo "✅ resume 完了。次回は再度 resume.sh を実行してください。"
