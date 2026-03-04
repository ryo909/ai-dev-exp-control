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
WORK_ROOT="$CONTROL_DIR/../.workdays"
SHORTLIST_FILE="$CONTROL_DIR/idea_bank/shortlist.json"

DAY_NUM=${1:?'Usage: run_day.sh <day_number>'}
DAY_STR=$(printf '%03d' "$DAY_NUM")
DAY_LABEL="Day${DAY_STR}"
REPO_NAME="ai-dev-day-${DAY_STR}"

GENRES=("productivity" "writing" "devtools" "planning" "learning" "health" "fun")
THEMES=("NeoLab" "Paper" "Noir" "Brutal" "Soft" "RetroTerminal" "Candy" "Mono")

ensure_gh_auth() {
  if gh api user -q '.login' >/dev/null 2>&1; then
    return 0
  fi

  if [ -z "${GH_TOKEN:-}" ] && [ -f "$HOME/.git-credentials" ]; then
    GH_TOKEN=$(sed -n 's#https://[^:]*:\([^@]*\)@github.com#\1#p' "$HOME/.git-credentials" | head -n 1 || true)
    if [ -n "$GH_TOKEN" ]; then
      export GH_TOKEN
    fi
  fi

  gh api user -q '.login' >/dev/null 2>&1 || {
    echo "❌ GitHub認証が必要です。gh auth login を実行してください。"
    exit 1
  }
}

select_theme() {
  local idx
  idx=$(( (DAY_NUM * 17 + 3) % ${#THEMES[@]} ))
  echo "${THEMES[$idx]}"
}

select_genre() {
  local idx offset candidate
  local -a recent
  mapfile -t recent < <(jq -r '.recent_genres[-2:][]?' "$STATE_FILE")

  idx=$((DAY_NUM % ${#GENRES[@]}))

  for ((offset=0; offset<${#GENRES[@]}; offset++)); do
    candidate="${GENRES[$(((idx + offset) % ${#GENRES[@]}))]}"
    if [[ " ${recent[*]} " != *" ${candidate} "* ]]; then
      echo "$candidate"
      return 0
    fi
  done

  echo "${GENRES[$idx]}"
}

generate_plan() {
  local genre="$1"
  case "$genre" in
    productivity)
      TITLE="Focus Slot Composer"
      DESCRIPTION="タスク時間を入力すると、集中ブロックと休憩を自動配置する。"
      CORE_ACTION="plan"
      TWIST="開始時刻つきでそのまま実行できるタイムスロットを提示"
      ONE_SENTENCE="作業時間から集中と休憩の実行順を自動で作る生産性ツール。"
      KEYWORDS='["focus","pomodoro","timebox","productivity"]'
      STORY_SUMMARY="時間管理の迷いをなくすため、実行順を即決できる構成にした。"
      ;;
    writing)
      TITLE="Draft Tightener"
      DESCRIPTION="下書きを貼ると、冗長表現を減らした短文案を作る。"
      CORE_ACTION="rewrite"
      TWIST="文字数の目安を表示してSNS向けの短文化を支援"
      ONE_SENTENCE="文章を短く整えて、投稿しやすい形に圧縮するライティングツール。"
      KEYWORDS='["writing","edit","summary","copy"]'
      STORY_SUMMARY="長い文章を公開前に圧縮する一手間を最小化した。"
      ;;
    devtools)
      TITLE="JSON Key Lens"
      DESCRIPTION="JSON文字列からキー構造を抽出して読みやすく表示する。"
      CORE_ACTION="inspect"
      TWIST="深いネストでもパス一覧を一気に展開できる"
      ONE_SENTENCE="JSONの構造を素早く把握するための開発者向けビューア。"
      KEYWORDS='["json","devtools","inspect","debug"]'
      STORY_SUMMARY="APIレスポンス調査を速くするため、構造確認に特化した。"
      ;;
    planning)
      TITLE="Backward Milestone Mapper"
      DESCRIPTION="締切から逆算して、中間マイルストーンを自動分割する。"
      CORE_ACTION="schedule"
      TWIST="逆算の根拠を1行で示して計画の納得感を上げる"
      ONE_SENTENCE="締切から逆算した実行計画を即作成するプランニングツール。"
      KEYWORDS='["planning","milestone","schedule","roadmap"]'
      STORY_SUMMARY="期限直前の混乱を減らすため、逆算起点の設計を採用した。"
      ;;
    learning)
      TITLE="Recall Loop Builder"
      DESCRIPTION="学習トピックから復習間隔つきのチェックリストを生成する。"
      CORE_ACTION="generate"
      TWIST="初回学習日から次回復習日を同時表示する"
      ONE_SENTENCE="学習内容の復習タイミングを自動で組み立てる学習支援ツール。"
      KEYWORDS='["learning","review","memory","study"]'
      STORY_SUMMARY="覚えたつもりを防ぐため、復習日を先に決める導線にした。"
      ;;
    health)
      TITLE="Hydration Pace Planner"
      DESCRIPTION="1日の目標水分量を時間帯ごとに分割して表示する。"
      CORE_ACTION="track"
      TWIST="勤務時間に合わせて飲水タイミングを均等化する"
      ONE_SENTENCE="目標水分量を無理なく達成するための配分プランナー。"
      KEYWORDS='["health","hydration","habit","wellness"]'
      STORY_SUMMARY="健康行動を続けやすくするため、負担の少ない配分にした。"
      ;;
    fun)
      TITLE="Tiny Prompt Play"
      DESCRIPTION="気分を選ぶと短いお題を3つ返す遊びツール。"
      CORE_ACTION="generate"
      TWIST="30秒で遊べるミニお題を即時に複数提案"
      ONE_SENTENCE="気分転換用の短いお題をすぐ作るライトな遊びツール。"
      KEYWORDS='["fun","prompt","game","idea"]'
      STORY_SUMMARY="作業の合間に使える短時間の遊び体験を目指した。"
      ;;
    *)
      echo "❌ 未知のgenre: $genre"
      exit 1
      ;;
  esac
}

apply_shortlist_injection() {
  [ -f "$SHORTLIST_FILE" ] || return 0
  local items_len idx source title stags source_short title_short

  items_len=$(jq -r '[.items[]? | select((.tags // []) | index("collector_error") | not)] | length' "$SHORTLIST_FILE" 2>/dev/null || echo "0")
  [[ "$items_len" =~ ^[0-9]+$ ]] || return 0
  [ "$items_len" -gt 0 ] || return 0

  idx=$((DAY_NUM % items_len))
  source=$(jq -r --argjson i "$idx" '[.items[]? | select((.tags // []) | index("collector_error") | not)] | .[$i].source // empty' "$SHORTLIST_FILE" 2>/dev/null || true)
  title=$(jq -r --argjson i "$idx" '[.items[]? | select((.tags // []) | index("collector_error") | not)] | .[$i].title // empty' "$SHORTLIST_FILE" 2>/dev/null || true)
  stags=$(jq -c --argjson i "$idx" '[.items[]? | select((.tags // []) | index("collector_error") | not)] | .[$i].tags // []' "$SHORTLIST_FILE" 2>/dev/null || echo "[]")

  [ -n "$source" ] || return 0
  [ -n "$title" ] || return 0

  source_short=$(printf '%s' "$source" | tr '\n' ' ' | cut -c1-18 | sed 's/[[:space:]]*$//')
  title_short=$(printf '%s' "$title" | tr '\n' ' ' | cut -c1-24 | sed 's/[[:space:]]*$//')

  TWIST="${TWIST} / Signal:${source_short}「${title_short}」"
  ONE_SENTENCE="${ONE_SENTENCE}（話題:${source_short}）"
  STORY_SUMMARY="${STORY_SUMMARY}｜Signal:${source_short}"
  KEYWORDS=$(jq -nc --argjson base "$KEYWORDS" --argjson extra "$stags" '$base + $extra + ["trend"] | unique')
}

sync_template_files() {
  local tmp_template
  tmp_template=$(mktemp -d "${WORK_ROOT}/template-XXXXXX")
  gh repo clone "${GH_USER}/${TEMPLATE_REPO}" "$tmp_template" >/dev/null
  (
    cd "$tmp_template"
    tar --exclude='.git' --exclude='node_modules' --exclude='dist' -cf - .
  ) | (
    cd "$WORK_DIR"
    tar -xf -
  )
  rm -rf "$tmp_template"
}

write_story_file() {
  local story_path="$1"
  cat > "$story_path" <<STORY
# ${DAY_LABEL} Story — ${TITLE}

## Why
毎日使う小さな課題を、1ページで即解決できる形にしたかったため。

## Requirements
- Webブラウザだけで完結すること
- 1画面で主要操作が終わること
- GitHub Pagesで公開できること

## Design highlights
- ${DAY_LABEL}専用にテーマをseed固定して再生成時の見た目を安定化
- ${GENRE}用途に寄せた単機能UIで迷いを減らす
- 出力をそのまま再利用できるテキスト構造

## Trade-offs / Known issues
- ローカル保存機能は未実装
- 複雑な入力バリデーションは最小限

## Next ideas
- 履歴保存
- プリセット追加
- エクスポート形式拡張

## Social copy
${DAY_LABEL}｜${TITLE}
${ONE_SENTENCE}
STORY
}

ensure_gh_auth
GH_USER=$(gh api user -q '.login')
PAGES_URL="https://${GH_USER}.github.io/${REPO_NAME}/"
REPO_URL="https://github.com/${GH_USER}/${REPO_NAME}"

echo "▶ ${DAY_LABEL}: ${REPO_NAME}"

EXISTING_STATUS=$(jq -r ".days[\"${DAY_STR}\"].status // empty" "$STATE_FILE")
if [ "$EXISTING_STATUS" = "done" ] || [ "$EXISTING_STATUS" = "posted" ]; then
  echo "  ⏭ ${DAY_LABEL} は既に完了済みです。スキップします。"
  exit 0
fi

echo "  [1/6] 企画生成..."
GENRE=$(select_genre)
THEME=$(select_theme)
generate_plan "$GENRE"
apply_shortlist_injection || true

echo "  [2/6] Repo作成..."
if ! gh repo view "${GH_USER}/${REPO_NAME}" >/dev/null 2>&1; then
  gh repo create "${GH_USER}/${REPO_NAME}" \
    --public \
    --template "${GH_USER}/${TEMPLATE_REPO}" \
    --description "AI個人開発実験 ${DAY_LABEL}" >/dev/null
fi

mkdir -p "$WORK_ROOT"
WORK_DIR=$(mktemp -d "$WORK_ROOT/${REPO_NAME}-XXXXXX")
gh repo clone "${GH_USER}/${REPO_NAME}" "$WORK_DIR" >/dev/null
cd "$WORK_DIR"
sync_template_files

echo "  [3/6] 実装..."
jq -n \
  --arg day "$DAY_LABEL" \
  --arg title "$TITLE" \
  --arg description "$DESCRIPTION" \
  --arg genre "$GENRE" \
  --arg theme "$THEME" \
  --arg story_summary "$STORY_SUMMARY" \
  --arg tool_name "$TITLE" \
  --arg core_action "$CORE_ACTION" \
  --arg twist "$TWIST" \
  --arg one_sentence "$ONE_SENTENCE" \
  --argjson keywords "$KEYWORDS" \
  --arg repo_name "$REPO_NAME" \
  --arg pages_url "$PAGES_URL" \
  '
  {
    day: $day,
    title: $title,
    description: $description,
    genre: $genre,
    theme: $theme,
    story_summary: $story_summary,
    tool_name: $tool_name,
    core_action: $core_action,
    twist: $twist,
    one_sentence: $one_sentence,
    keywords: $keywords,
    repo_name: $repo_name,
    pages_url: $pages_url
  }
' > meta.json

bash "$CONTROL_DIR/scripts/validate_json.sh" "$CONTROL_DIR/schemas/meta_schema.json" "meta.json"

sed -i -E "s#https://github.com/[^/]+/ai-dev-day-[0-9]{3}#${REPO_URL}#g" index.html

write_story_file "STORY.md"

cat > README.md <<README
# ${DAY_LABEL} — ${TITLE}

> ${ONE_SENTENCE}

## 使い方

1. ページを開く
2. 入力欄にテキストを入れる
3. 実行して結果を確認する

## Story

- [制作ストーリー](./STORY.md)

## Demo

🌐 [GitHub Pages](${PAGES_URL})

---

${DAY_LABEL} / #100日開発
README

echo "  [4/6] Build & Smoke Gate..."
npm ci --silent || npm install --silent
npm run build >/dev/null
if [ ! -f "dist/index.html" ]; then
  echo "❌ Smoke Gate 不合格: dist/index.html が見つかりません"
  exit 1
fi

echo "  [4.5/6] Capture demo (optional)..."
bash "$CONTROL_DIR/scripts/capture_assets.sh" "$WORK_DIR" || echo "⚠ capture skipped"

echo "  [5/6] Push & Pages..."
git add meta.json README.md STORY.md index.html public/media 2>/dev/null \
  || git add meta.json README.md STORY.md index.html
git commit -m "${DAY_LABEL}: scaffold ${TITLE}" >/dev/null || true
git -c credential.helper=store push origin main >/dev/null

gh api -X PUT "repos/${GH_USER}/${REPO_NAME}/pages" -f "build_type=workflow" >/dev/null 2>&1 \
  || gh api -X POST "repos/${GH_USER}/${REPO_NAME}/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1 \
  || true
gh api -X PUT "repos/${GH_USER}/${REPO_NAME}/pages" -f "build_type=workflow" >/dev/null 2>&1 || true

echo "  [6/6] STATE更新..."
POST_STANDARD_LEGACY="${DAY_LABEL}｜${TITLE}
${ONE_SENTENCE}
${PAGES_URL}
#個人開発 #100日開発"

POST_STANDARD="$POST_STANDARD_LEGACY"
if command -v python3 >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/render_post_text.py" ]; then
  if POST_STANDARD_RENDERED=$(python3 "$SCRIPT_DIR/render_post_text.py" \
    --day "$DAY_STR" \
    --tool-name "$TITLE" \
    --pages-url "$PAGES_URL" \
    --body-id "A" \
    --one-liner "$ONE_SENTENCE" \
    --use-case "用途: ${DESCRIPTION}" 2>/dev/null); then
    POST_STANDARD="$POST_STANDARD_RENDERED"
    echo "  ℹ 投稿テンプレ適用: templates/posts (body_A)"
  else
    echo "  ℹ 投稿テンプレ未適用: 従来方式にフォールバック"
  fi
fi

TITLE_SHORT=$(echo "$TITLE" | cut -c1-16)
DESC_SHORT=$(echo "$ONE_SENTENCE" | cut -c1-24)
POST_COMPACT="${DAY_LABEL}|${TITLE_SHORT}
${DESC_SHORT}
${PAGES_URL}
#個人開発 #100日開発"

POST_MINIMAL="${DAY_LABEL}|${TITLE_SHORT}
${PAGES_URL}
#個人開発 #100日開発"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cd "$CONTROL_DIR"
jq --arg now "$NOW" \
   --arg day "$DAY_STR" \
   --arg repo_name "$REPO_NAME" \
   --arg repo_url "$REPO_URL" \
   --arg pages_url "$PAGES_URL" \
   --arg tool_name "$TITLE" \
   --arg title "$TITLE" \
   --arg description "$DESCRIPTION" \
   --arg genre "$GENRE" \
   --arg theme "$THEME" \
   --arg story_summary "$STORY_SUMMARY" \
   --arg core_action "$CORE_ACTION" \
   --arg twist "$TWIST" \
   --arg one_sentence "$ONE_SENTENCE" \
   --argjson keywords "$KEYWORDS" \
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
       title: $title,
       description: $description,
       genre: $genre,
       theme: $theme,
       story_summary: $story_summary,
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
   | .next_day = (($day | tonumber) + 1)
   | .recent_meta = ((.recent_meta + [{
       day: $day,
       core_action: $core_action,
       twist: $twist,
       one_sentence: $one_sentence
     }]) | .[-20:])
   | .recent_genres = (((.recent_genres // []) + [$genre]) | .[-3:])
   | .last_run_at = $now
   | .execution_logs = ((.execution_logs // []) + [{
       executed_at: $now,
       day: $day,
       repo_name: $repo_name,
       genre: $genre,
       theme: $theme,
       steps: ["planning", "implementation", "build", "publish", "state_update"],
       status: "done"
     }])
' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

git add "$STATE_FILE"
git commit -m "state: ${DAY_LABEL} completed" >/dev/null || true

echo "  ✅ ${DAY_LABEL} 全工程完了"
