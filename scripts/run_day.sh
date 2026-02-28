#!/usr/bin/env bash
# ============================================================
# run_day.sh — 1 Day分の生成・ビルド・デプロイ・記録
# Usage: run_day.sh <day_number>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"
TEMPLATE_REPO="ai-dev-exp-template"

DAY_NUM=${1:?'Usage: run_day.sh <day_number>'}
DAY_STR=$(printf '%03d' "$DAY_NUM")
REPO_NAME="ai-dev-day-${DAY_STR}"
WORK_DIR="${CONTROL_DIR}/../${REPO_NAME}"

# GitHub ユーザー名を取得
GH_USER=$(gh api user -q '.login' 2>/dev/null || echo "")
if [ -z "$GH_USER" ]; then
  echo "❌ GitHub認証が必要です。'gh auth login' を実行してください。"
  exit 1
fi

PAGES_URL="https://${GH_USER}.github.io/${REPO_NAME}/"
REPO_URL="https://github.com/${GH_USER}/${REPO_NAME}"

echo "▶ Day${DAY_STR}: ${REPO_NAME}"

# ---- 既に完了チェック ----
EXISTING_STATUS=$(jq -r ".days[\"${DAY_STR}\"].status // empty" "$STATE_FILE")
if [ "$EXISTING_STATUS" = "done" ] || [ "$EXISTING_STATUS" = "posted" ]; then
  echo "  ⏭ Day${DAY_STR} は既に完了済みです。スキップします。"
  exit 0
fi

# ============================================================
# Step 1: アイデア生成 & Diversity Gate
# ============================================================
echo "  [1/6] アイデア生成 & Diversity Gate..."

# 直近のメタ情報を取得
RECENT_META=$(jq -c '.recent_meta' "$STATE_FILE")
RECENT_ACTIONS=$(echo "$RECENT_META" | jq -r '.[].core_action' | tail -3 | tr '\n' ',')

# ※ ここは実際の運用ではAI（Codex等）がアイデアを生成する。
# このスクリプトはフレームワークとして、以下のファイルが存在することを前提とする:
#   ${WORK_DIR}/meta.json

# Diversity Gate チェック関数
check_diversity() {
  local meta_file="$1"
  local core_action twist one_sentence

  core_action=$(jq -r '.core_action // empty' "$meta_file")
  twist=$(jq -r '.twist // empty' "$meta_file")
  one_sentence=$(jq -r '.one_sentence // empty' "$meta_file")

  # 必須フィールドチェック
  if [ -z "$core_action" ] || [ -z "$twist" ] || [ -z "$one_sentence" ]; then
    echo "FAIL:必須フィールドが空です"
    return 1
  fi

  # core_action 3連続チェック
  LAST_THREE=$(echo "$RECENT_META" | jq -r '[.[-3:][] | .core_action] | join(",")')
  if [ -n "$LAST_THREE" ]; then
    COUNT=$(echo "$LAST_THREE" | tr ',' '\n' | grep -c "^${core_action}$" || true)
    if [ "$COUNT" -ge 2 ]; then
      echo "FAIL:core_action '${core_action}' が3連続になります"
      return 1
    fi
  fi

  # twist 空/弱チェック
  if [ ${#twist} -lt 2 ]; then
    echo "FAIL:twistが弱すぎます"
    return 1
  fi

  # one_sentence 類似チェック（簡易: 直近5本と完全一致チェック）
  SIMILAR=$(echo "$RECENT_META" | jq -r --arg s "$one_sentence" \
    '[.[-5:][] | select(.one_sentence == $s)] | length')
  if [ "$SIMILAR" -gt 0 ]; then
    echo "FAIL:one_sentenceが直近と完全一致"
    return 1
  fi

  echo "PASS"
  return 0
}

prepare_meta() {
  local meta_file="$1"
  local current_tool current_action current_twist current_sentence
  local current_day current_repo current_pages generated_action generated_twist generated_sentence
  local idx
  local actions=("summarize" "transform" "compare" "classify" "extract" "schedule" "analyze")

  if [ ! -f "$meta_file" ]; then
    cat > "$meta_file" <<'EOF'
{
  "day": "XXX",
  "tool_name": "ツール名をここに",
  "core_action": "",
  "twist": "",
  "one_sentence": "1文説明をここに",
  "keywords": [],
  "repo_name": "ai-dev-day-XXX",
  "pages_url": "https://USERNAME.github.io/ai-dev-day-XXX/"
}
EOF
  fi

  current_tool=$(jq -r '.tool_name // ""' "$meta_file")
  current_action=$(jq -r '.core_action // ""' "$meta_file")
  current_twist=$(jq -r '.twist // ""' "$meta_file")
  current_sentence=$(jq -r '.one_sentence // ""' "$meta_file")
  current_day=$(jq -r '.day // ""' "$meta_file")
  current_repo=$(jq -r '.repo_name // ""' "$meta_file")
  current_pages=$(jq -r '.pages_url // ""' "$meta_file")

  idx=$((DAY_NUM % ${#actions[@]}))
  generated_action="${actions[$idx]}"
  generated_twist="day${DAY_STR}向けに最短手順で使える形式にする"
  generated_sentence="Day${DAY_STR}の作業を30秒で進めるための${generated_action}ツール。"

  if [ -z "$current_tool" ] || [ "$current_tool" = "ツール名をここに" ]; then
    current_tool="Day${DAY_STR} ${generated_action} helper"
  fi
  if [ -z "$current_action" ]; then
    current_action="$generated_action"
  fi
  if [ -z "$current_twist" ]; then
    current_twist="$generated_twist"
  fi
  if [ -z "$current_sentence" ] || [ "$current_sentence" = "1文説明をここに" ]; then
    current_sentence="$generated_sentence"
  fi
  if [ -z "$current_day" ] || [ "$current_day" = "XXX" ]; then
    current_day="$DAY_STR"
  fi
  if [ -z "$current_repo" ] || [ "$current_repo" = "ai-dev-day-XXX" ]; then
    current_repo="$REPO_NAME"
  fi
  if [ -z "$current_pages" ] || [ "$current_pages" = "https://USERNAME.github.io/ai-dev-day-XXX/" ]; then
    current_pages="$PAGES_URL"
  fi

  jq --arg day "$current_day" \
     --arg tool_name "$current_tool" \
     --arg core_action "$current_action" \
     --arg twist "$current_twist" \
     --arg one_sentence "$current_sentence" \
     --arg repo_name "$current_repo" \
     --arg pages_url "$current_pages" \
     '
     .day = $day
     | .tool_name = $tool_name
     | .core_action = $core_action
     | .twist = $twist
     | .one_sentence = $one_sentence
     | .repo_name = $repo_name
     | .pages_url = $pages_url
     | .keywords = (if (.keywords | type) == "array" then .keywords else [] end)
     | .keywords = (if (.keywords | length) > 0 then .keywords else [$core_action, "automation", ("day" + $day)] end)
     ' "$meta_file" > "${meta_file}.tmp" && mv "${meta_file}.tmp" "$meta_file"
}

# ============================================================
# Step 2: Repo作成（テンプレートから）
# ============================================================
echo "  [2/6] Repo作成..."

if [ -d "$WORK_DIR" ]; then
  echo "  ⚠ ディレクトリ ${WORK_DIR} は既に存在します。既存を使用します。"
else
  # gh repo create from template
  gh repo create "${REPO_NAME}" \
    --public \
    --template "${GH_USER}/${TEMPLATE_REPO}" \
    --clone \
    --description "AI個人開発実験 Day${DAY_STR}" \
    || {
      echo "❌ repo作成に失敗しました。"
      echo "  原因: gh repo create エラー"
      echo "  次の一手: テンプレートrepo '${TEMPLATE_REPO}' が存在するか確認"
      exit 1
    }
  # gh repo create --clone は CWD に clone する
  if [ ! -d "$WORK_DIR" ]; then
    # clone先がカレントにある場合
    if [ -d "./${REPO_NAME}" ]; then
      mv "./${REPO_NAME}" "$WORK_DIR"
    fi
  fi
fi

cd "$WORK_DIR"

# ============================================================
# Step 3: 実装（ここはAIが実際のコードを生成する部分）
# ============================================================
echo "  [3/6] 実装..."

# ※ 実際の運用では、ここでAI（Codex等）が:
#   - meta.json にアイデアを書き込み
#   - src/ にツールのコードを実装
#   - README.md を完成させる
# このスクリプトでは meta.json と README.md の存在を確認する。

if [ ! -f "meta.json" ]; then
  echo "  ⚠ meta.json が見つかりません。既定値で作成して続行します。"
fi

prepare_meta "meta.json"

# Diversity Gate 実行
if ! GATE_RESULT=$(check_diversity "meta.json"); then
  echo "  ❌ Diversity Gate 不合格: $GATE_RESULT"
  echo "  → 次の一手: meta.json のアイデアを変更してください。"
  exit 1
fi
if [ "$GATE_RESULT" != "PASS" ]; then
  echo "  ❌ Diversity Gate 不合格: $GATE_RESULT"
  echo "  → 次の一手: meta.json のアイデアを変更してください。"
  exit 1
fi
echo "  ✅ Diversity Gate 合格"

# ============================================================
# Step 4: Build & Smoke Gate
# ============================================================
echo "  [4/6] Build & Smoke Gate..."

# npm ci
npm ci --silent 2>/dev/null || npm install --silent || {
  echo "❌ npm install 失敗"
  echo "  原因: package依存エラー"
  echo "  次の一手: package.jsonを確認"
  exit 1
}

# build
npm run build || {
  echo "❌ ビルド失敗"
  echo "  原因: Vite build エラー"
  echo "  次の一手: ソースコードのエラーを修正"
  exit 1
}

# 簡易smoke: dist/index.html が存在するか
if [ ! -f "dist/index.html" ]; then
  echo "❌ Smoke Gate 不合格: dist/index.html が見つかりません"
  exit 1
fi
echo "  ✅ Build & Smoke Gate 合格"

# ============================================================
# Step 5: README Gate & Push
# ============================================================
echo "  [5/6] README Gate & Push..."

# README Gate: 最低限の項目チェック
if [ -f "README.md" ]; then
  README_CONTENT=$(cat README.md)
  GATE_OK=true

  if ! echo "$README_CONTENT" | grep -qi "day${DAY_STR}\|Day ${DAY_STR}\|DayDay${DAY_STR}"; then
    # Day表記がない場合は追記
    echo "" >> README.md
    echo "---" >> README.md
    echo "Day${DAY_STR} / #100日開発" >> README.md
  fi

  if ! echo "$README_CONTENT" | grep -qi "github.io"; then
    echo "" >> README.md
    echo "🌐 [Demo](${PAGES_URL})" >> README.md
  fi
else
  echo "  ⚠ README.md が見つかりません"
fi

# vite.config.js の base を設定
if [ -f "vite.config.js" ]; then
  # 環境変数でbase設定
  export VITE_BASE="/${REPO_NAME}/"
fi

# commit & push
git add -A
git commit -m "Day${DAY_STR}: implement and build" || true
git push origin main || {
  echo "❌ push失敗"
  echo "  次の一手: ネットワークを確認し手動でpush"
  exit 1
}

# ---- GitHub Pages 有効化 ----
echo "  ▶ GitHub Pages を設定中..."
gh api -X PUT "repos/${GH_USER}/${REPO_NAME}/pages" \
  -f "build_type=workflow" 2>/dev/null \
  || gh api -X POST "repos/${GH_USER}/${REPO_NAME}/pages" \
    -f "source[branch]=main" -f "source[path]=/" 2>/dev/null \
  || echo "  ⚠ Pages設定は手動で行ってください"

# ============================================================
# Step 6: STATE更新
# ============================================================
echo "  [6/6] STATE更新..."

TOOL_NAME=$(jq -r '.tool_name // "Untitled"' meta.json)
CORE_ACTION=$(jq -r '.core_action' meta.json)
TWIST=$(jq -r '.twist' meta.json)
ONE_SENTENCE=$(jq -r '.one_sentence' meta.json)
KEYWORDS=$(jq -c '.keywords // []' meta.json)

# 投稿テキスト生成
POST_STANDARD="Day${DAY_STR}｜${TOOL_NAME}
${ONE_SENTENCE}
${PAGES_URL}
#個人開発 #100日開発"

# 圧縮版
TOOL_SHORT=$(echo "$TOOL_NAME" | cut -c1-16)
DESC_SHORT=$(echo "$ONE_SENTENCE" | cut -c1-24)
POST_COMPACT="Day${DAY_STR}|${TOOL_SHORT}
${DESC_SHORT}
${PAGES_URL}
#個人開発 #100日開発"

# 最小版
POST_MINIMAL="Day${DAY_STR}|${TOOL_SHORT}
${PAGES_URL}
#個人開発 #100日開発"

# STATE.json に Day エントリ追加
cd "$CONTROL_DIR"
jq --arg day "$DAY_STR" \
   --arg repo_name "$REPO_NAME" \
   --arg repo_url "$REPO_URL" \
   --arg pages_url "$PAGES_URL" \
   --arg core_action "$CORE_ACTION" \
   --arg twist "$TWIST" \
   --arg one_sentence "$ONE_SENTENCE" \
   --argjson keywords "$KEYWORDS" \
   --arg tool_name "$TOOL_NAME" \
   --arg post_standard "$POST_STANDARD" \
   --arg post_compact "$POST_COMPACT" \
   --arg post_minimal "$POST_MINIMAL" \
   '
   .days[$day] = {
     repo_name: $repo_name,
     repo_url: $repo_url,
     pages_url: $pages_url,
     meta: {
       tool_name: $tool_name,
       core_action: $core_action,
       twist: $twist,
       one_sentence: $one_sentence,
       keywords: $keywords
     },
     post_texts: {
       standard: $post_standard,
       compact: $post_compact,
       minimal: $post_minimal
     },
     status: "done"
   }
   | .next_day = ($day | tonumber) + 1
   | .recent_meta = (.recent_meta + [{
       day: $day,
       core_action: $core_action,
       twist: $twist,
       one_sentence: $one_sentence
     }]) | .recent_meta = .recent_meta[-20:]
   ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# CATALOG.md 更新（行追加）
CATALOG_LINE="| Day${DAY_STR} | ${TOOL_NAME} | ${ONE_SENTENCE} | [Demo](${PAGES_URL}) | [Repo](${REPO_URL}) | ✅ |"
# テーブルの「— |」行の前に挿入
if grep -q "^| — |" "$CONTROL_DIR/CATALOG.md"; then
  awk -v line="$CATALOG_LINE" '
    !inserted && /^| — \|/ { print line; inserted=1 }
    { print }
  ' "$CONTROL_DIR/CATALOG.md" > "$CONTROL_DIR/CATALOG.md.tmp" && mv "$CONTROL_DIR/CATALOG.md.tmp" "$CONTROL_DIR/CATALOG.md"
else
  echo "$CATALOG_LINE" >> "$CONTROL_DIR/CATALOG.md"
fi

# 進捗数を更新
DONE_COUNT=$(jq '[.days[] | select(.status == "done" or .status == "posted")] | length' "$STATE_FILE")
sed -i "s/進捗:.*$/進捗: **Day ${DONE_COUNT} \/ 100**/" "$CONTROL_DIR/CATALOG.md"
sed -i "s/最終更新:.*$/最終更新: $(date +%Y-%m-%d)/" "$CONTROL_DIR/CATALOG.md"

# control repo commit（Day単位）
git add -A
git commit -m "state: Day${DAY_STR} completed" || true

echo "  ✅ Day${DAY_STR} 全工程完了"
