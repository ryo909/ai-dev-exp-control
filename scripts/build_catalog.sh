#!/usr/bin/env bash
# ============================================================
# build_catalog.sh — catalog.json → index.html & latest.json 更新
# STATE.jsonから catalog.json を再生成し、Pages反映用にcommit
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"
CATALOG_DIR="$CONTROL_DIR/catalog"

echo "▶ カタログ更新中..."

# ---- catalog.json を STATE.json から生成 ----
jq '
  [.days | to_entries[] | {
    day: .key,
    tool_name: .value.meta.tool_name,
    one_sentence: .value.meta.one_sentence,
    core_action: .value.meta.core_action,
    twist: .value.meta.twist,
    keywords: .value.meta.keywords,
    repo_name: .value.repo_name,
    repo_url: .value.repo_url,
    pages_url: .value.pages_url,
    status: .value.status
  }] | sort_by(.day)
' "$STATE_FILE" > "$CATALOG_DIR/catalog.json"

echo "  ✅ catalog.json 更新完了"

# ---- latest.json を生成（直近7本） ----
jq '
  [.days | to_entries[] | select(.value.status == "done" or .value.status == "posted") | {
    day: .key,
    tool_name: .value.meta.tool_name,
    one_sentence: .value.meta.one_sentence,
    pages_url: .value.pages_url,
    repo_url: .value.repo_url,
    status: .value.status
  }] | sort_by(.day) | .[-7:]
' "$STATE_FILE" > "$CATALOG_DIR/latest.json"

echo "  ✅ latest.json 更新完了"

# ---- CATALOG.md をSTATEから再生成 ----
DONE_COUNT=$(jq '[.days[] | select(.status == "done" or .status == "posted")] | length' "$STATE_FILE")
CATALOG_MD="$CONTROL_DIR/CATALOG.md"

{
  echo "# CATALOG.md — Day一覧（人間向け）"
  echo ""
  echo "> 進捗: **Day ${DONE_COUNT} / 100**  "
  echo "> 最終更新: $(date +%Y-%m-%d)"
  echo ""
  echo "---"
  echo ""
  echo "## 一覧"
  echo ""
  echo "| Day | ツール名 | 説明 | Pages URL | Repo URL | Status |"
  echo "|-----|---------|------|-----------|----------|--------|"

  # STATE.json の days を Day順にリスト
  jq -r '
    .days | to_entries | sort_by(.key)[] |
    "| Day\(.key) | \(.value.meta.tool_name) | \(.value.meta.one_sentence) | [Demo](\(.value.pages_url)) | [Repo](\(.value.repo_url)) | \(if .value.status == "done" or .value.status == "posted" then "✅" else "⏳" end) |"
  ' "$STATE_FILE"

  if [ "$DONE_COUNT" -eq 0 ]; then
    echo "| — | — | — | — | — | — |"
  fi

  echo ""
  echo "---"
  echo ""
  echo "_このファイルは \`scripts/build_catalog.sh\` により自動更新されます。_"
} > "$CATALOG_MD"

echo "  ✅ CATALOG.md 更新完了"

# ---- commit (push は run_batch.sh に任せる) ----
cd "$CONTROL_DIR"
git add catalog/ CATALOG.md
git commit -m "catalog: update $(date +%Y-%m-%d)" || true

echo "✅ カタログ更新完了"
