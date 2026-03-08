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
COMPLEXITY_PROFILES_FILE="$CONTROL_DIR/system/complexity_profiles.json"
COMPONENT_PACKS_FILE="$CONTROL_DIR/system/component_packs.json"
NEXT_BATCH_PLAN_FILE="$CONTROL_DIR/plans/next_batch_plan.json"
PLAN_CATALOG_FILE="$CONTROL_DIR/system/plan_catalog.json"

DAY_NUM=${1:?'Usage: run_day.sh <day_number>'}
DAY_STR=$(printf '%03d' "$DAY_NUM")
DAY_LABEL="Day${DAY_STR}"
REPO_NAME="ai-dev-day-${DAY_STR}"
ENHANCED_CANDIDATES_FILE="$CONTROL_DIR/plans/candidates/day${DAY_STR}_enhanced_candidates.json"
NOVELTY_SELECTION_FILE="$CONTROL_DIR/plans/candidates/day${DAY_STR}_novelty_selection.json"
FORCE_REGENERATE="${FORCE_REGENERATE:-0}"
DIVERSITY_LOOKBACK_DAYS="${DIVERSITY_LOOKBACK_DAYS:-14}"

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

select_complexity_tier() {
  local idx
  idx=$(( (DAY_NUM - 1) % 7 ))
  if [ "$idx" -le 3 ]; then
    echo "small"
  elif [ "$idx" -le 5 ]; then
    echo "medium"
  else
    echo "large"
  fi
}

set_plan_metadata_defaults() {
  FAMILY="${FAMILY:-${GENRE}_single_tool}"
  MECHANIC="${MECHANIC:-single_step_transform}"
  INPUT_STYLE="${INPUT_STYLE:-text_area}"
  OUTPUT_STYLE="${OUTPUT_STYLE:-result_panel}"
  AUDIENCE_PROMISE="${AUDIENCE_PROMISE:-quick_task_completion}"
  PUBLISH_HOOK="${PUBLISH_HOOK:-1分で使えるミニツール}"
  ENGINE="${ENGINE:-default_transform}"
}

resolve_selected_components() {
  local tier="$1"
  SELECTED_COMPONENTS_JSON="[]"
  COMPLEXITY_PROMPT_HINT="Keep the tool single-purpose and stable."

  if [ -f "$COMPLEXITY_PROFILES_FILE" ] && [ -f "$COMPONENT_PACKS_FILE" ]; then
    SELECTED_COMPONENTS_JSON=$(jq -nc \
      --arg tier "$tier" \
      --argfile profiles "$COMPLEXITY_PROFILES_FILE" \
      --argfile packs "$COMPONENT_PACKS_FILE" '
      ($profiles[$tier].preferred_components // []) as $pref
      | ($profiles[$tier].recommended_count // ($pref | length)) as $n
      | [$pref[] | select($packs[.] != null)]
      | .[:$n]
    ' 2>/dev/null || echo "[]")
  fi

  case "$tier" in
    small)
      COMPLEXITY_PROMPT_HINT="Keep the tool single-purpose and stable. Add at most one safe enhancement component."
      ;;
    medium)
      COMPLEXITY_PROMPT_HINT="Add 2 safe enhancement components from selected_components while keeping the app single-page and stable."
      ;;
    large)
      COMPLEXITY_PROMPT_HINT="Create a showpiece version by adding around 3 safe enhancement components from selected_components, but avoid risky architecture changes."
      ;;
  esac
}

load_next_batch_recommendation() {
  NEXT_BATCH_REC_JSON="{}"
  NEXT_BATCH_SLOT_JSON="null"
  NEXT_BATCH_PLAN_SOURCE=""
  NEXT_BATCH_RECOMMENDED_COMPONENTS_JSON="[]"
  NEXT_BATCH_RECOMMENDED_ENHANCEMENT="false"
  NEXT_BATCH_RECOMMENDED_COUNT=0
  NEXT_BATCH_RECOMMENDED_COMPLEXITY=""

  if [ "${USE_NEXT_BATCH_PLAN:-0}" != "1" ]; then
    return 0
  fi

  if [ ! -x "$CONTROL_DIR/scripts/read_next_batch_plan.sh" ]; then
    echo "  ℹ next_batch recommendation skipped: reader script missing"
    return 0
  fi

  NEXT_BATCH_REC_JSON=$(bash "$CONTROL_DIR/scripts/read_next_batch_plan.sh" --day "$DAY_STR" --plan "$NEXT_BATCH_PLAN_FILE" 2>/dev/null || echo "{}")
  if ! jq -e 'type=="object"' >/dev/null 2>&1 <<<"$NEXT_BATCH_REC_JSON"; then
    NEXT_BATCH_REC_JSON="{}"
  fi
  if [ "$(jq -r 'keys | length' <<<"$NEXT_BATCH_REC_JSON")" -eq 0 ]; then
    echo "  ℹ next_batch recommendation skipped: no slot recommendation"
    return 0
  fi

  NEXT_BATCH_PLAN_SOURCE="plans/next_batch_plan.json"
  NEXT_BATCH_SLOT_JSON=$(jq -c '.slot // null' <<<"$NEXT_BATCH_REC_JSON")
  NEXT_BATCH_RECOMMENDED_COMPONENTS_JSON=$(jq -c '.recommended_components // []' <<<"$NEXT_BATCH_REC_JSON")
  NEXT_BATCH_RECOMMENDED_ENHANCEMENT=$(jq -r '.adopt_competitor_enhancement // false | tostring' <<<"$NEXT_BATCH_REC_JSON")
  NEXT_BATCH_RECOMMENDED_COUNT=$(jq -r '.recommended_component_count // 0' <<<"$NEXT_BATCH_REC_JSON")
  NEXT_BATCH_RECOMMENDED_COMPLEXITY=$(jq -r '.recommended_complexity_tier // empty' <<<"$NEXT_BATCH_REC_JSON")
  echo "  ℹ next_batch recommendation loaded: slot=$(jq -r '.slot' <<<"$NEXT_BATCH_REC_JSON"), tier=${NEXT_BATCH_RECOMMENDED_COMPLEXITY:-none}"
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
      FAMILY="focus_slot"
      MECHANIC="time_blocking"
      INPUT_STYLE="time_budget"
      OUTPUT_STYLE="time_slots"
      AUDIENCE_PROMISE="clear_execution_order"
      PUBLISH_HOOK="開始時刻つきでそのまま使える"
      ENGINE="habit_slots"
      ;;
    writing)
      TITLE="Draft Tightener"
      DESCRIPTION="下書きを貼ると、冗長表現を減らした短文案を作る。"
      CORE_ACTION="rewrite"
      TWIST="文字数の目安を表示してSNS向けの短文化を支援"
      ONE_SENTENCE="文章を短く整えて、投稿しやすい形に圧縮するライティングツール。"
      KEYWORDS='["writing","edit","summary","copy"]'
      STORY_SUMMARY="長い文章を公開前に圧縮する一手間を最小化した。"
      FAMILY="writing_tightener"
      MECHANIC="compression"
      INPUT_STYLE="paragraph_text"
      OUTPUT_STYLE="short_copy"
      AUDIENCE_PROMISE="faster_posting"
      PUBLISH_HOOK="長文をすぐ短文化"
      ENGINE="copy_angle"
      ;;
    devtools)
      TITLE="JSON Key Lens"
      DESCRIPTION="JSON文字列からキー構造を抽出して読みやすく表示する。"
      CORE_ACTION="inspect"
      TWIST="深いネストでもパス一覧を一気に展開できる"
      ONE_SENTENCE="JSONの構造を素早く把握するための開発者向けビューア。"
      KEYWORDS='["json","devtools","inspect","debug"]'
      STORY_SUMMARY="APIレスポンス調査を速くするため、構造確認に特化した。"
      FAMILY="json_structure"
      MECHANIC="tree_extraction"
      INPUT_STYLE="json_sample"
      OUTPUT_STYLE="path_list"
      AUDIENCE_PROMISE="faster_debugging"
      PUBLISH_HOOK="JSON構造を即把握"
      ENGINE="json_paths"
      ;;
    planning)
      TITLE="Backward Milestone Mapper"
      DESCRIPTION="締切から逆算して、中間マイルストーンを自動分割する。"
      CORE_ACTION="schedule"
      TWIST="逆算の根拠を1行で示して計画の納得感を上げる"
      ONE_SENTENCE="締切から逆算した実行計画を即作成するプランニングツール。"
      KEYWORDS='["planning","milestone","schedule","roadmap"]'
      STORY_SUMMARY="期限直前の混乱を減らすため、逆算起点の設計を採用した。"
      FAMILY="milestone_backward"
      MECHANIC="reverse_planning"
      INPUT_STYLE="deadline_and_tasks"
      OUTPUT_STYLE="milestone_plan"
      AUDIENCE_PROMISE="deadline_confidence"
      PUBLISH_HOOK="締切逆算で計画が決まる"
      ENGINE="agenda_builder"
      ;;
    learning)
      TITLE="Recall Loop Builder"
      DESCRIPTION="学習トピックから復習間隔つきのチェックリストを生成する。"
      CORE_ACTION="generate"
      TWIST="初回学習日から次回復習日を同時表示する"
      ONE_SENTENCE="学習内容の復習タイミングを自動で組み立てる学習支援ツール。"
      KEYWORDS='["learning","review","memory","study"]'
      STORY_SUMMARY="覚えたつもりを防ぐため、復習日を先に決める導線にした。"
      FAMILY="review_scheduler"
      MECHANIC="spaced_repetition"
      INPUT_STYLE="topic_list"
      OUTPUT_STYLE="review_schedule"
      AUDIENCE_PROMISE="higher_retention"
      PUBLISH_HOOK="復習日を即決める"
      ENGINE="qa_rotator"
      ;;
    health)
      TITLE="Hydration Pace Planner"
      DESCRIPTION="1日の目標水分量を時間帯ごとに分割して表示する。"
      CORE_ACTION="track"
      TWIST="勤務時間に合わせて飲水タイミングを均等化する"
      ONE_SENTENCE="目標水分量を無理なく達成するための配分プランナー。"
      KEYWORDS='["health","hydration","habit","wellness"]'
      STORY_SUMMARY="健康行動を続けやすくするため、負担の少ない配分にした。"
      FAMILY="hydration_planner"
      MECHANIC="slot_distribution"
      INPUT_STYLE="goal_amount"
      OUTPUT_STYLE="intake_slots"
      AUDIENCE_PROMISE="habit_consistency"
      PUBLISH_HOOK="飲水配分を自動提案"
      ENGINE="habit_slots"
      ;;
    fun)
      TITLE="Tiny Prompt Play"
      DESCRIPTION="気分を選ぶと短いお題を3つ返す遊びツール。"
      CORE_ACTION="generate"
      TWIST="30秒で遊べるミニお題を即時に複数提案"
      ONE_SENTENCE="気分転換用の短いお題をすぐ作るライトな遊びツール。"
      KEYWORDS='["fun","prompt","game","idea"]'
      STORY_SUMMARY="作業の合間に使える短時間の遊び体験を目指した。"
      FAMILY="prompt_game"
      MECHANIC="prompt_shuffle"
      INPUT_STYLE="mood_selector"
      OUTPUT_STYLE="mini_prompts"
      AUDIENCE_PROMISE="quick_refresh"
      PUBLISH_HOOK="30秒で遊べる"
      ENGINE="constraint_game"
      ;;
    *)
      echo "❌ 未知のgenre: $genre"
      exit 1
      ;;
  esac
  set_plan_metadata_defaults
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

select_novel_plan() {
  [ -f "$PLAN_CATALOG_FILE" ] || return 1
  [[ "$DIVERSITY_LOOKBACK_DAYS" =~ ^[0-9]+$ ]] || DIVERSITY_LOOKBACK_DAYS=14

  local generated_at selection_json
  generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  selection_json=$(jq -nc \
    --slurpfile state "$STATE_FILE" \
    --slurpfile catalog "$PLAN_CATALOG_FILE" \
    --arg day "$DAY_STR" \
    --arg generated_at "$generated_at" \
    --argjson lookback "$DIVERSITY_LOOKBACK_DAYS" '
    def pad3($n):
      ($n | tostring) as $s
      | if ($s | length) == 1 then "00" + $s
        elif ($s | length) == 2 then "0" + $s
        else $s
        end;
    def infer_family($m):
      if (($m.family // "") | length) > 0 then $m.family
      elif (($m.title // $m.tool_name // "") == "Draft Tightener") then "writing_tightener"
      elif (($m.title // $m.tool_name // "") == "JSON Key Lens") then "json_structure"
      elif (($m.title // $m.tool_name // "") == "Backward Milestone Mapper") then "milestone_backward"
      elif (($m.title // $m.tool_name // "") == "Recall Loop Builder") then "review_scheduler"
      elif (($m.title // $m.tool_name // "") == "Hydration Pace Planner") then "hydration_planner"
      elif (($m.title // $m.tool_name // "") == "Tiny Prompt Play") then "prompt_game"
      elif (($m.title // $m.tool_name // "") == "Focus Slot Composer") then "focus_slot"
      else (($m.genre // "misc") + "_generic")
      end;
    def infer_mechanic($m):
      if (($m.mechanic // "") | length) > 0 then $m.mechanic
      else (($m.core_action // "generic") + "_flow")
      end;
    def infer_input_style($m):
      if (($m.input_style // "") | length) > 0 then $m.input_style
      else "text_area"
      end;
    def infer_output_style($m):
      if (($m.output_style // "") | length) > 0 then $m.output_style
      else "result_panel"
      end;
    def infer_audience($m):
      if (($m.audience_promise // "") | length) > 0 then $m.audience_promise
      else "quick_task_completion"
      end;
    ($day | tonumber) as $dayn
    | (if $lookback < 1 then 14 else $lookback end) as $lb
    | ($dayn - $lb) as $raw_start
    | (if $raw_start < 1 then 1 else $raw_start end) as $start
    | [
        range($start; $dayn) as $n
        | ($state[0].days[pad3($n)] // null) as $entry
        | select($entry | type == "object")
        | ($entry.meta // {}) as $m
        | {
            day: pad3($n),
            title: ($m.title // $m.tool_name // ""),
            genre: ($m.genre // ""),
            core_action: ($m.core_action // ""),
            theme: ($m.theme // ""),
            family: infer_family($m),
            mechanic: infer_mechanic($m),
            input_style: infer_input_style($m),
            output_style: infer_output_style($m),
            audience_promise: infer_audience($m)
          }
      ] as $recent
    | (($catalog[0].items // [])) as $items
    | [
        $items[] as $c
        | ([ $recent[] | select(.title == ($c.title // "")) ] | length) as $title_hits
        | ([ $recent[] | select(.family == ($c.family // "")) ] | length) as $family_hits
        | ([ $recent[] | select(.theme == ($c.theme // "")) ] | length) as $theme_hits
        | ([ $recent[] | select(.mechanic == ($c.mechanic // "")) ] | length) as $mechanic_hits
        | ([ $recent[] | select(.input_style == ($c.input_style // "")) ] | length) as $input_hits
        | ([ $recent[] | select(.output_style == ($c.output_style // "")) ] | length) as $output_hits
        | ([ $recent[] | select(.audience_promise == ($c.audience_promise // "")) ] | length) as $audience_hits
        | ([ $recent[] | select(.core_action == ($c.core_action // "")) ] | length) as $core_hits
        | ([ $recent[] | select(.genre == ($c.genre // "")) ] | length) as $genre_hits
        | [
            (if $title_hits > 0 then {code:"title_overlap_recent", count:$title_hits, penalty:130} else empty end),
            (if $family_hits > 0 then {code:"family_overlap_recent", count:$family_hits, penalty:(80 * $family_hits)} else empty end),
            (if $theme_hits > 0 then {code:"theme_overlap_recent", count:$theme_hits, penalty:(28 * $theme_hits)} else empty end),
            (if $mechanic_hits > 0 then {code:"mechanic_overlap_recent", count:$mechanic_hits, penalty:(35 * $mechanic_hits)} else empty end),
            (if $input_hits > 0 then {code:"input_overlap_recent", count:$input_hits, penalty:(35 * $input_hits)} else empty end),
            (if $output_hits > 0 then {code:"output_overlap_recent", count:$output_hits, penalty:(18 * $output_hits)} else empty end),
            (if $audience_hits > 0 then {code:"audience_overlap_recent", count:$audience_hits, penalty:(35 * $audience_hits)} else empty end),
            (if $core_hits > 1 then {code:"core_action_repeated", count:$core_hits, penalty:(12 * ($core_hits - 1))} else empty end),
            (if $genre_hits > 1 then {code:"genre_repeated", count:$genre_hits, penalty:(8 * ($genre_hits - 1))} else empty end)
          ] as $penalties
        | (100 - (([ $penalties[].penalty ] | add) // 0)) as $score
        | {
            id: $c.id,
            title: $c.title,
            description: $c.description,
            genre: $c.genre,
            theme: $c.theme,
            core_action: $c.core_action,
            twist: $c.twist,
            one_sentence: $c.one_sentence,
            story_summary: $c.story_summary,
            keywords: ($c.keywords // []),
            family: $c.family,
            mechanic: $c.mechanic,
            input_style: $c.input_style,
            output_style: $c.output_style,
            audience_promise: $c.audience_promise,
            publish_hook: $c.publish_hook,
            engine: ($c.engine // "default_transform"),
            score: $score,
            penalties: $penalties
          }
      ] as $ranked_raw
    | ($ranked_raw | sort_by(-.score, .id)) as $ranked
    | {
        generated_at: $generated_at,
        day: ("Day" + $day),
        lookback_days: $lb,
        policy: {
          note: "penalize similarity against recent days and within-batch updates",
          reject_when_near_duplicate: true
        },
        recent_reference: $recent,
        selected: ($ranked[0] // null),
        ranked_candidates: $ranked,
        rejected_candidates: [ $ranked[] | select(.score < 60) | {id, title, score, penalties} ]
      }
  ')

  [ -n "$selection_json" ] || return 1
  if ! jq -e '.selected != null' >/dev/null 2>&1 <<<"$selection_json"; then
    return 1
  fi

  printf '%s\n' "$selection_json" > "$NOVELTY_SELECTION_FILE"
  TITLE=$(jq -r '.selected.title' <<<"$selection_json")
  DESCRIPTION=$(jq -r '.selected.description' <<<"$selection_json")
  GENRE=$(jq -r '.selected.genre' <<<"$selection_json")
  THEME=$(jq -r '.selected.theme' <<<"$selection_json")
  CORE_ACTION=$(jq -r '.selected.core_action' <<<"$selection_json")
  TWIST=$(jq -r '.selected.twist' <<<"$selection_json")
  ONE_SENTENCE=$(jq -r '.selected.one_sentence' <<<"$selection_json")
  STORY_SUMMARY=$(jq -r '.selected.story_summary' <<<"$selection_json")
  KEYWORDS=$(jq -c '.selected.keywords // []' <<<"$selection_json")
  FAMILY=$(jq -r '.selected.family // empty' <<<"$selection_json")
  MECHANIC=$(jq -r '.selected.mechanic // empty' <<<"$selection_json")
  INPUT_STYLE=$(jq -r '.selected.input_style // empty' <<<"$selection_json")
  OUTPUT_STYLE=$(jq -r '.selected.output_style // empty' <<<"$selection_json")
  AUDIENCE_PROMISE=$(jq -r '.selected.audience_promise // empty' <<<"$selection_json")
  PUBLISH_HOOK=$(jq -r '.selected.publish_hook // empty' <<<"$selection_json")
  ENGINE=$(jq -r '.selected.engine // "default_transform"' <<<"$selection_json")
  set_plan_metadata_defaults
  return 0
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

resolve_ui_copy() {
  case "$CORE_ACTION" in
    diagnose) ACTION_LABEL="切り分ける" ;;
    generate) ACTION_LABEL="生成する" ;;
    rewrite) ACTION_LABEL="言い換える" ;;
    summarize) ACTION_LABEL="要約する" ;;
    outline) ACTION_LABEL="構成化する" ;;
    schedule) ACTION_LABEL="配分する" ;;
    prioritize) ACTION_LABEL="優先度化する" ;;
    route) ACTION_LABEL="振り分ける" ;;
    review) ACTION_LABEL="棚卸しする" ;;
    estimate) ACTION_LABEL="見積もる" ;;
    plan) ACTION_LABEL="計画化する" ;;
    map) ACTION_LABEL="マップ化する" ;;
    stabilize) ACTION_LABEL="整える" ;;
    *) ACTION_LABEL="実行する" ;;
  esac

  case "$INPUT_STYLE" in
    json_sample) INPUT_LABEL="JSONサンプル"; INPUT_PLACEHOLDER='{user:{id:1,name:A}}' ;;
    error_log_paste) INPUT_LABEL="エラーログ"; INPUT_PLACEHOLDER='2026-03-08T12:00Z ERROR payment timeout status=504' ;;
    topic_list) INPUT_LABEL="トピック"; INPUT_PLACEHOLDER=$'認証設計\n監視設計\n運用手順' ;;
    risk_rows) INPUT_LABEL="リスク行"; INPUT_PLACEHOLDER=$'認証遅延|5|4\n通知失敗|4|3' ;;
    option_notes) INPUT_LABEL="選択肢メモ"; INPUT_PLACEHOLDER=$'A案: 即実装\nB案: 先に検証' ;;
    paragraph_text) INPUT_LABEL="本文"; INPUT_PLACEHOLDER='難しい説明文をここに貼り付けます。' ;;
    question_list) INPUT_LABEL="質問リスト"; INPUT_PLACEHOLDER=$'Q. 料金は?\nQ. 解約方法は?' ;;
    experience_notes) INPUT_LABEL="経験メモ"; INPUT_PLACEHOLDER=$'課題: リリース遅延\n行動: 進捗可視化を導入' ;;
    confusion_notes) INPUT_LABEL="曖昧ポイント"; INPUT_PLACEHOLDER=$'useEffect依存配列の使い分け\nキャッシュ無効化の条件' ;;
    time_range) INPUT_LABEL="時刻条件"; INPUT_PLACEHOLDER='現在 02:00 就寝 / 10:00 起床, 目標 23:30 就寝 / 07:30 起床' ;;
    ingredient_list) INPUT_LABEL="食材リスト"; INPUT_PLACEHOLDER=$'鶏むね肉\nブロッコリー\n卵' ;;
    trigger_notes) INPUT_LABEL="トリガーメモ"; INPUT_PLACEHOLDER=$'通知が連続すると焦る\n締切前に思考停止する' ;;
    interruption_list) INPUT_LABEL="割り込み要因"; INPUT_PLACEHOLDER=$'チャット通知\n会議割り込み\nメール確認癖' ;;
    task_sequence) INPUT_LABEL="タスク遷移"; INPUT_PLACEHOLDER=$'設計->実装->レビュー->会議->実装' ;;
    weekly_notes) INPUT_LABEL="週次メモ"; INPUT_PLACEHOLDER=$'継続: 朝レビュー\n停止: 夜更かし\n実験: 昼散歩' ;;
    constraints) INPUT_LABEL="制約条件"; INPUT_PLACEHOLDER='2人 / 10分 / 道具なし / 室内' ;;
    concept_phrase) INPUT_LABEL="説明したい概念"; INPUT_PLACEHOLDER='レートリミット' ;;
    trip_conditions) INPUT_LABEL="移動条件"; INPUT_PLACEHOLDER='1泊2日 / 電車移動 / 雨予報 / 荷物少なめ' ;;
    memo_lines) INPUT_LABEL="断片メモ"; INPUT_PLACEHOLDER=$'画面遷移後にクラッシュ\niOS17で再現' ;;
    role_and_tasks) INPUT_LABEL="役割と初週タスク"; INPUT_PLACEHOLDER=$'role: backend\n初週: API把握, 監視導線' ;;
    task_rows) INPUT_LABEL="課題リスト"; INPUT_PLACEHOLDER=$'請求API修正|今週|高\nFAQ更新|来週|中' ;;
    feature_bullets) INPUT_LABEL="機能箇条書き"; INPUT_PLACEHOLDER=$'無制限プロジェクト\nCSV出力\nチーム権限' ;;
    *) INPUT_LABEL="入力"; INPUT_PLACEHOLDER="ここに入力..." ;;
  esac

  case "$OUTPUT_STYLE" in
    triage_steps) OUTPUT_LABEL="初動切り分け" ;;
    schema_draft) OUTPUT_LABEL="スキーマ下書き" ;;
    repro_report) OUTPUT_LABEL="再現手順テンプレ" ;;
    agenda_timeline) OUTPUT_LABEL="アジェンダ配分" ;;
    priority_matrix) OUTPUT_LABEL="優先度マトリクス" ;;
    onboarding_plan) OUTPUT_LABEL="初週オンボーディング案" ;;
    three_lane_board) OUTPUT_LABEL="3レーン振り分け" ;;
    decision_memo) OUTPUT_LABEL="判断メモ" ;;
    article_outline) OUTPUT_LABEL="記事骨子" ;;
    simplified_copy) OUTPUT_LABEL="平文化案" ;;
    copy_variants) OUTPUT_LABEL="訴求バリエーション" ;;
    star_outline) OUTPUT_LABEL="STAR骨子" ;;
    question_set) OUTPUT_LABEL="確認問題セット" ;;
    gap_map) OUTPUT_LABEL="前提不足マップ" ;;
    daily_slots) OUTPUT_LABEL="段階調整プラン" ;;
    prep_timeline) OUTPUT_LABEL="作り置き段取り" ;;
    calm_steps) OUTPUT_LABEL="鎮静手順カード" ;;
    defense_playbook) OUTPUT_LABEL="遮断プレイブック" ;;
    cost_report) OUTPUT_LABEL="切替コスト見積" ;;
    action_ledger) OUTPUT_LABEL="次週アクション台帳" ;;
    challenge_cards) OUTPUT_LABEL="チャレンジお題" ;;
    analogy_set) OUTPUT_LABEL="比喩セット" ;;
    packing_list) OUTPUT_LABEL="持ち物リスト" ;;
    *) OUTPUT_LABEL="結果" ;;
  esac

  INPUT_PLACEHOLDER_SINGLE=$(printf '%s' "$INPUT_PLACEHOLDER" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
  INPUT_PLACEHOLDER_HTML=$(printf '%s' "$INPUT_PLACEHOLDER_SINGLE" | sed -e 's/&/\&amp;/g' -e 's/\"/\&quot;/g' -e "s/'/&#39;/g" -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
}

write_index_file() {
  cat > index.html <<HTML
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${DAY_LABEL} — ${TITLE}</title>
  <meta name="description" content="${ONE_SENTENCE}">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Noto+Sans+JP:wght@400;500;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/src/style.css">
</head>
<body>
  <div id="app">
    <header class="app-header">
      <div class="header-badge">${DAY_LABEL}</div>
      <h1 class="header-title">${TITLE}</h1>
      <p class="header-desc">${ONE_SENTENCE}</p>
    </header>
    <main class="app-main">
      <section class="tool-area">
        <div class="input-group">
          <label for="toolInput" class="input-label">${INPUT_LABEL}</label>
          <textarea id="toolInput" class="input-textarea" rows="6" placeholder="${INPUT_PLACEHOLDER_HTML}"></textarea>
        </div>
        <button id="actionBtn" class="btn-primary">${ACTION_LABEL}</button>
        <div class="output-group" id="outputGroup" style="display:none">
          <label class="input-label">${OUTPUT_LABEL}</label>
          <div id="toolOutput" class="output-area"></div>
        </div>
      </section>
    </main>
    <footer class="app-footer">
      <span>${DAY_LABEL} — ${PUBLISH_HOOK}</span>
      <a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a>
    </footer>
  </div>
  <script type="module" src="/src/main.js"></script>
</body>
</html>
HTML
}

write_main_script() {
  local profile_json
  profile_json=$(jq -nc \
    --arg day "$DAY_LABEL" \
    --arg title "$TITLE" \
    --arg one_sentence "$ONE_SENTENCE" \
    --arg core_action "$CORE_ACTION" \
    --arg family "$FAMILY" \
    --arg mechanic "$MECHANIC" \
    --arg input_style "$INPUT_STYLE" \
    --arg output_style "$OUTPUT_STYLE" \
    --arg audience_promise "$AUDIENCE_PROMISE" \
    --arg publish_hook "$PUBLISH_HOOK" \
    --arg engine "$ENGINE" \
    '{day:$day,title:$title,one_sentence:$one_sentence,core_action:$core_action,family:$family,mechanic:$mechanic,input_style:$input_style,output_style:$output_style,audience_promise:$audience_promise,publish_hook:$publish_hook,engine:$engine}')

  {
    echo "import './style.css';"
    printf 'const PROFILE = %s;\n' "$profile_json"
    cat <<'JS'
const actionBtn = document.getElementById('actionBtn');
const toolInput = document.getElementById('toolInput');
const toolOutput = document.getElementById('toolOutput');
const outputGroup = document.getElementById('outputGroup');

actionBtn.addEventListener('click', () => {
  const input = (toolInput.value || '').trim();
  if (!input) {
    showOutput('⚠ 入力を入れてください', 'warning');
    return;
  }
  const result = processInput(input);
  showOutput(result, 'success');
});

function processInput(input) {
  switch (PROFILE.engine) {
    case 'json_paths':
      return renderJsonPaths(input);
    case 'agenda_builder':
      return buildAgenda(input);
    case 'risk_matrix':
      return buildRiskMatrix(input);
    case 'decision_brief':
      return buildDecisionBrief(input);
    case 'checklist_builder':
      return buildChecklist(input);
    case 'qa_rotator':
      return buildQuestionRotation(input);
    case 'habit_slots':
      return buildHabitSlots(input);
    case 'triage_router':
      return buildTriage(input);
    case 'copy_angle':
      return buildCopyAngles(input);
    case 'story_weaver':
      return buildStoryOutline(input);
    case 'constraint_game':
      return buildConstraints(input);
    case 'incident_card':
      return buildIncidentCard(input);
    default:
      return fallbackAnalyze(input);
  }
}

function renderJsonPaths(input) {
  let obj;
  try {
    obj = JSON.parse(input);
  } catch (e) {
    return 'JSONとして解釈できませんでした。まずJSON形式で入力してください。';
  }
  const rows = [];
  walk(obj, '$', rows);
  return ['JSON path summary:', ...rows.slice(0, 80)].join('\\n');
}

function walk(node, path, rows) {
  if (Array.isArray(node)) {
    rows.push(`${path} : array(${node.length})`);
    node.forEach((x, i) => walk(x, `${path}[${i}]`, rows));
    return;
  }
  if (node && typeof node === 'object') {
    rows.push(`${path} : object`);
    Object.keys(node).forEach((k) => walk(node[k], `${path}.${k}`, rows));
    return;
  }
  rows.push(`${path} : ${typeof node}`);
}

function splitLines(input) {
  return input.split(/\\n+/).map((x) => x.trim()).filter(Boolean);
}

function buildAgenda(input) {
  const topics = splitLines(input);
  const per = Math.max(5, Math.floor(45 / Math.max(topics.length, 1)));
  const lines = topics.map((t, i) => `${String(i + 1).padStart(2, '0')}. ${t} (${per}分)`);
  return ['Agenda draft:', ...lines, 'Closing: 決定事項と担当を1分で確認'].join('\\n');
}

function buildRiskMatrix(input) {
  const rows = splitLines(input).map((line) => {
    const [name, impactRaw, probRaw] = line.split('|').map((x) => (x || '').trim());
    const impact = Number(impactRaw || 3);
    const prob = Number(probRaw || 3);
    const score = impact * prob;
    return { name: name || line, impact, prob, score };
  }).sort((a, b) => b.score - a.score);
  const out = rows.map((r, i) => `${i + 1}. ${r.name} | impact=${r.impact} prob=${r.prob} score=${r.score}`);
  return ['Risk priority:', ...out.slice(0, 20)].join('\\n');
}

function buildDecisionBrief(input) {
  const rows = splitLines(input);
  const outline = rows.map((x, i) => `${i + 1}) ${x}`);
  return [
    'Decision memo draft',
    '背景: 何を決めるかを1行で明記',
    '選択肢:',
    ...outline,
    '採用理由: 影響と実行速度のバランス',
    '却下理由: 維持コストまたはリスクが高い'
  ].join('\\n');
}

function buildChecklist(input) {
  const rows = splitLines(input);
  const checks = rows.map((x, i) => `- [ ] ${x} を確認する (${i + 1})`);
  return ['Checklist:', ...checks.slice(0, 30)].join('\\n');
}

function buildQuestionRotation(input) {
  const rows = splitLines(input);
  const out = [];
  rows.forEach((x) => {
    out.push(`基礎: ${x}とは?`);
    out.push(`応用: ${x}を使う判断基準は?`);
    out.push(`確認: ${x}を説明できるか?`);
  });
  return ['Question rotation:', ...out.slice(0, 24)].join('\\n');
}

function buildHabitSlots(input) {
  const rows = splitLines(input);
  if (rows.length === 0) {
    return '条件を1行以上入力してください。';
  }
  return [
    'Habit slots:',
    '朝: 5分の準備タスク',
    '昼: 進捗確認',
    '夜: 翌日の障害を1つ潰す',
    `メモ: ${rows[0]}`
  ].join('\\n');
}

function buildTriage(input) {
  const rows = splitLines(input);
  const lanes = { now: [], later: [], delegate: [] };
  rows.forEach((r, i) => {
    if (i % 3 === 0) lanes.now.push(r);
    else if (i % 3 === 1) lanes.later.push(r);
    else lanes.delegate.push(r);
  });
  return [
    'Triage lanes:',
    '[Now]', ...lanes.now.map((x) => `- ${x}`),
    '[Later]', ...lanes.later.map((x) => `- ${x}`),
    '[Delegate]', ...lanes.delegate.map((x) => `- ${x}`)
  ].join('\\n');
}

function buildCopyAngles(input) {
  const seed = splitLines(input).slice(0, 3).join(' / ');
  return [
    'Copy angles:',
    `1) 課題起点: ${seed} で困る時間を減らす`,
    `2) 成果起点: ${seed} を最短で形にする`,
    `3) 安心起点: ${seed} のミスを事前に防ぐ`
  ].join('\\n');
}

function buildStoryOutline(input) {
  const rows = splitLines(input);
  return [
    'STAR outline:',
    `S: ${rows[0] || '背景を1行で記述'}`,
    `T: ${rows[1] || '目標を1行で記述'}`,
    `A: ${rows[2] || '取った行動を3点で記述'}`,
    `R: ${rows[3] || '成果を数値で記述'}`
  ].join('\\n');
}

function buildConstraints(input) {
  const rows = splitLines(input);
  const base = rows[0] || input;
  return [
    'Challenge cards:',
    `- 5分: ${base} で1つ作る`,
    `- 10分: ${base} を2通りで試す`,
    `- 15分: ${base} を他人に説明する`
  ].join('\\n');
}

function buildIncidentCard(input) {
  const rows = splitLines(input);
  return [
    'Incident first-response card:',
    `1. 事象要約: ${rows[0] || '症状を1行で記述'}`,
    '2. 影響範囲を確認',
    '3. 一時回避策を定義',
    '4. 恒久対応の仮説を列挙',
    '5. 共有先と次回更新時刻を明記'
  ].join('\\n');
}

function fallbackAnalyze(input) {
  const chars = input.length;
  const lines = input.split('\\n').length;
  const words = input.split(/\\s+/).filter(Boolean).length;
  return `分析結果\\n- chars: ${chars}\\n- words: ${words}\\n- lines: ${lines}`;
}

function showOutput(content, type = 'info') {
  outputGroup.style.display = '';
  toolOutput.className = `output-area output-${type}`;
  toolOutput.textContent = content;
  outputGroup.style.animation = 'none';
  outputGroup.offsetHeight;
  outputGroup.style.animation = 'fadeSlideIn 0.3s ease';
}
JS
  } > src/main.js
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
- Family: ${FAMILY}
- Mechanic: ${MECHANIC}
- Input/Output: ${INPUT_STYLE} -> ${OUTPUT_STYLE}
- Audience Promise: ${AUDIENCE_PROMISE}
- Publish Hook: ${PUBLISH_HOOK}
- Complexity Tier: ${COMPLEXITY_TIER}
- Selected components: ${SELECTED_COMPONENTS_TEXT}
- Complexity hint: ${COMPLEXITY_PROMPT_HINT}

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
  if [ "$FORCE_REGENERATE" = "1" ]; then
    echo "  ♻ ${DAY_LABEL} は既存完了済みですが FORCE_REGENERATE=1 のため再生成します。"
  else
    echo "  ⏭ ${DAY_LABEL} は既に完了済みです。スキップします。"
    exit 0
  fi
fi

echo "  [1/6] 企画生成..."
COMPLEXITY_TIER=$(select_complexity_tier)
if select_novel_plan; then
  echo "  ℹ novelty plan selected: ${TITLE} (family=${FAMILY}, engine=${ENGINE})"
else
  GENRE=$(select_genre)
  THEME=$(select_theme)
  generate_plan "$GENRE"
  echo "  ℹ novelty selector unavailable; fallback plan used"
fi
apply_shortlist_injection || true
set_plan_metadata_defaults

ADOPTED_NEXT_BATCH_COMPLEXITY="false"
ADOPTED_NEXT_BATCH_COMPONENTS="false"
ADOPTED_NEXT_BATCH_ENHANCEMENT="false"
NEXT_BATCH_PLAN_SOURCE_META=""
NEXT_BATCH_SLOT_META_JSON="null"
NEXT_BATCH_RECOMMENDED_COMPONENTS_META_JSON="[]"
NEXT_BATCH_RECOMMENDED_ENHANCEMENT_META="false"

load_next_batch_recommendation

if [ -n "${NEXT_BATCH_RECOMMENDED_COMPLEXITY:-}" ] && [ "${ADOPT_NEXT_BATCH_COMPLEXITY:-0}" = "1" ]; then
  COMPLEXITY_TIER="$NEXT_BATCH_RECOMMENDED_COMPLEXITY"
  ADOPTED_NEXT_BATCH_COMPLEXITY="true"
  NEXT_BATCH_PLAN_SOURCE_META="$NEXT_BATCH_PLAN_SOURCE"
  NEXT_BATCH_SLOT_META_JSON="$NEXT_BATCH_SLOT_JSON"
  echo "  ℹ next_batch complexity adopted: ${COMPLEXITY_TIER}"
fi

resolve_selected_components "$COMPLEXITY_TIER"

if [ "${ADOPT_NEXT_BATCH_COMPONENTS:-0}" = "1" ] && [ "$(jq -r 'length' <<<"$NEXT_BATCH_RECOMMENDED_COMPONENTS_JSON")" -gt 0 ]; then
  if [ "$NEXT_BATCH_RECOMMENDED_COUNT" -le 0 ]; then
    NEXT_BATCH_RECOMMENDED_COUNT=$(jq -r 'length' <<<"$NEXT_BATCH_RECOMMENDED_COMPONENTS_JSON")
  fi
  SELECTED_COMPONENTS_JSON=$(jq -c --argjson arr "$NEXT_BATCH_RECOMMENDED_COMPONENTS_JSON" --argjson n "$NEXT_BATCH_RECOMMENDED_COUNT" '$arr[:$n]' 2>/dev/null || echo "[]")
  ADOPTED_NEXT_BATCH_COMPONENTS="true"
  NEXT_BATCH_PLAN_SOURCE_META="${NEXT_BATCH_PLAN_SOURCE_META:-$NEXT_BATCH_PLAN_SOURCE}"
  NEXT_BATCH_SLOT_META_JSON="${NEXT_BATCH_SLOT_META_JSON:-$NEXT_BATCH_SLOT_JSON}"
  NEXT_BATCH_RECOMMENDED_COMPONENTS_META_JSON="$SELECTED_COMPONENTS_JSON"
  echo "  ℹ next_batch components adopted: $(jq -r 'join(\", \")' <<<"$SELECTED_COMPONENTS_JSON")"
fi

NEXT_BATCH_RECOMMENDED_ENHANCEMENT_META="$NEXT_BATCH_RECOMMENDED_ENHANCEMENT"
SELECTED_COMPONENTS_TEXT=$(jq -r 'if length == 0 then "none" else join(", ") end' <<<"$SELECTED_COMPONENTS_JSON")

ORIGINAL_TWIST="$TWIST"
ORIGINAL_ONE_SENTENCE="$ONE_SENTENCE"
ENHANCEMENT_ADOPTED="false"
ENHANCEMENT_SOURCE=""
ENHANCEMENT_CANDIDATE_ID=""

if [ -x "$CONTROL_DIR/scripts/build_enhanced_plan_candidates.sh" ]; then
  bash "$CONTROL_DIR/scripts/build_enhanced_plan_candidates.sh" \
    --day "$DAY_STR" \
    --genre "$GENRE" \
    --theme "$THEME" \
    --core-action "$CORE_ACTION" \
    --twist "$TWIST" \
    --one-sentence "$ONE_SENTENCE" || true
fi

if [ -f "$ENHANCED_CANDIDATES_FILE" ]; then
  echo "  ℹ enhanced plan candidates found: plans/candidates/day${DAY_STR}_enhanced_candidates.json"
  ENHANCEMENT_ALLOW=0
  if [ "${ADOPT_ENHANCED_PLAN:-0}" = "1" ]; then
    ENHANCEMENT_ALLOW=1
  fi
  if [ "${ADOPT_NEXT_BATCH_ENHANCEMENT:-0}" = "1" ] && [ "$NEXT_BATCH_RECOMMENDED_ENHANCEMENT" = "true" ]; then
    ENHANCEMENT_ALLOW=1
  fi
  if [ "$ENHANCEMENT_ALLOW" -eq 1 ]; then
    REC_ID=$(jq -r '.recommended_candidate_id // empty' "$ENHANCED_CANDIDATES_FILE" 2>/dev/null || true)
    if [ -n "$REC_ID" ]; then
      CAND_TWIST=$(jq -r --arg id "$REC_ID" '.candidates[]? | select(.id == $id) | .twist // empty' "$ENHANCED_CANDIDATES_FILE" 2>/dev/null || true)
      CAND_ONE_SENTENCE=$(jq -r --arg id "$REC_ID" '.candidates[]? | select(.id == $id) | .one_sentence // empty' "$ENHANCED_CANDIDATES_FILE" 2>/dev/null || true)
      CAND_SOURCE=$(jq -r '.source_competitor_scan // empty' "$ENHANCED_CANDIDATES_FILE" 2>/dev/null || true)
      if [ -n "$CAND_TWIST" ] && [ -n "$CAND_ONE_SENTENCE" ]; then
        TWIST="$CAND_TWIST"
        ONE_SENTENCE="$CAND_ONE_SENTENCE"
        ENHANCEMENT_ADOPTED="true"
        ENHANCEMENT_SOURCE="$CAND_SOURCE"
        ENHANCEMENT_CANDIDATE_ID="$REC_ID"
        if [ "${ADOPT_NEXT_BATCH_ENHANCEMENT:-0}" = "1" ] && [ "$NEXT_BATCH_RECOMMENDED_ENHANCEMENT" = "true" ]; then
          ADOPTED_NEXT_BATCH_ENHANCEMENT="true"
          NEXT_BATCH_PLAN_SOURCE_META="${NEXT_BATCH_PLAN_SOURCE_META:-$NEXT_BATCH_PLAN_SOURCE}"
          NEXT_BATCH_SLOT_META_JSON="${NEXT_BATCH_SLOT_META_JSON:-$NEXT_BATCH_SLOT_JSON}"
        fi
        echo "  ℹ enhanced plan adopted: ${REC_ID}"
      else
        echo "  ℹ enhanced plan not adopted: recommended candidate incomplete"
      fi
    else
      echo "  ℹ enhanced plan not adopted: recommended candidate missing"
    fi
  fi
fi

if [ "${USE_NEXT_BATCH_PLAN:-0}" = "1" ] && [ "$ADOPTED_NEXT_BATCH_COMPLEXITY" != "true" ] && [ "$ADOPTED_NEXT_BATCH_COMPONENTS" != "true" ] && [ "$ADOPTED_NEXT_BATCH_ENHANCEMENT" != "true" ]; then
  echo "  ℹ next_batch recommendation loaded but not adopted (flags off or conditions unmet)"
fi

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
  --arg complexity_tier "$COMPLEXITY_TIER" \
  --arg complexity_prompt_hint "$COMPLEXITY_PROMPT_HINT" \
  --arg tool_name "$TITLE" \
  --arg core_action "$CORE_ACTION" \
  --arg twist "$TWIST" \
  --arg one_sentence "$ONE_SENTENCE" \
  --arg family "$FAMILY" \
  --arg mechanic "$MECHANIC" \
  --arg input_style "$INPUT_STYLE" \
  --arg output_style "$OUTPUT_STYLE" \
  --arg audience_promise "$AUDIENCE_PROMISE" \
  --arg publish_hook "$PUBLISH_HOOK" \
  --arg engine "$ENGINE" \
  --arg original_twist "$ORIGINAL_TWIST" \
  --arg original_one_sentence "$ORIGINAL_ONE_SENTENCE" \
  --arg enhancement_source "$ENHANCEMENT_SOURCE" \
  --arg enhancement_candidate_id "$ENHANCEMENT_CANDIDATE_ID" \
  --arg enhancement_adopted "$ENHANCEMENT_ADOPTED" \
  --arg adopted_next_batch_complexity "$ADOPTED_NEXT_BATCH_COMPLEXITY" \
  --arg adopted_next_batch_components "$ADOPTED_NEXT_BATCH_COMPONENTS" \
  --arg adopted_next_batch_enhancement "$ADOPTED_NEXT_BATCH_ENHANCEMENT" \
  --arg next_batch_plan_source "$NEXT_BATCH_PLAN_SOURCE_META" \
  --arg next_batch_recommended_enhancement "$NEXT_BATCH_RECOMMENDED_ENHANCEMENT_META" \
  --argjson next_batch_slot "$NEXT_BATCH_SLOT_META_JSON" \
  --argjson next_batch_recommended_components "$NEXT_BATCH_RECOMMENDED_COMPONENTS_META_JSON" \
  --argjson selected_components "$SELECTED_COMPONENTS_JSON" \
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
    complexity_tier: $complexity_tier,
    selected_components: $selected_components,
    complexity_prompt_hint: $complexity_prompt_hint,
    story_summary: $story_summary,
    tool_name: $tool_name,
    core_action: $core_action,
    twist: $twist,
    one_sentence: $one_sentence,
    family: $family,
    mechanic: $mechanic,
    input_style: $input_style,
    output_style: $output_style,
    audience_promise: $audience_promise,
    publish_hook: $publish_hook,
    engine: $engine,
    original_twist: $original_twist,
    original_one_sentence: $original_one_sentence,
    enhancement_source: $enhancement_source,
    enhancement_candidate_id: $enhancement_candidate_id,
    enhancement_adopted: ($enhancement_adopted == "true"),
    adopted_next_batch_complexity: ($adopted_next_batch_complexity == "true"),
    adopted_next_batch_components: ($adopted_next_batch_components == "true"),
    adopted_next_batch_enhancement: ($adopted_next_batch_enhancement == "true"),
    next_batch_plan_source: $next_batch_plan_source,
    next_batch_slot: $next_batch_slot,
    next_batch_recommended_components: $next_batch_recommended_components,
    next_batch_recommended_enhancement: ($next_batch_recommended_enhancement == "true"),
    keywords: $keywords,
    repo_name: $repo_name,
    pages_url: $pages_url
  }
' > meta.json

bash "$CONTROL_DIR/scripts/validate_json.sh" "$CONTROL_DIR/schemas/meta_schema.json" "meta.json"

resolve_ui_copy
write_index_file
write_main_script
write_story_file "STORY.md"

cat > README.md <<README
# ${DAY_LABEL} — ${TITLE}

> ${ONE_SENTENCE}
>
> Complexity Tier: ${COMPLEXITY_TIER}
>
> Selected Components: ${SELECTED_COMPONENTS_TEXT}
>
> Family / Mechanic: ${FAMILY} / ${MECHANIC}
>
> Input -> Output: ${INPUT_STYLE} -> ${OUTPUT_STYLE}
>
> Audience Promise: ${AUDIENCE_PROMISE}

## 使い方

1. ページを開く
2. ${INPUT_LABEL}を入力する
3. 「${ACTION_LABEL}」を実行する
4. ${OUTPUT_LABEL}を確認して必要に応じて再入力する

## Story

- [制作ストーリー](./STORY.md)
- Complexity hint: ${COMPLEXITY_PROMPT_HINT}
- Publish hook: ${PUBLISH_HOOK}

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
git add meta.json README.md STORY.md index.html src/main.js public/media 2>/dev/null \
  || git add meta.json README.md STORY.md index.html src/main.js
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
   --arg complexity_tier "$COMPLEXITY_TIER" \
   --arg complexity_prompt_hint "$COMPLEXITY_PROMPT_HINT" \
   --arg core_action "$CORE_ACTION" \
   --arg twist "$TWIST" \
   --arg one_sentence "$ONE_SENTENCE" \
   --arg family "$FAMILY" \
   --arg mechanic "$MECHANIC" \
   --arg input_style "$INPUT_STYLE" \
   --arg output_style "$OUTPUT_STYLE" \
   --arg audience_promise "$AUDIENCE_PROMISE" \
   --arg publish_hook "$PUBLISH_HOOK" \
   --arg engine "$ENGINE" \
   --arg original_twist "$ORIGINAL_TWIST" \
   --arg original_one_sentence "$ORIGINAL_ONE_SENTENCE" \
   --arg enhancement_source "$ENHANCEMENT_SOURCE" \
   --arg enhancement_candidate_id "$ENHANCEMENT_CANDIDATE_ID" \
   --arg enhancement_adopted "$ENHANCEMENT_ADOPTED" \
   --arg adopted_next_batch_complexity "$ADOPTED_NEXT_BATCH_COMPLEXITY" \
   --arg adopted_next_batch_components "$ADOPTED_NEXT_BATCH_COMPONENTS" \
   --arg adopted_next_batch_enhancement "$ADOPTED_NEXT_BATCH_ENHANCEMENT" \
   --arg next_batch_plan_source "$NEXT_BATCH_PLAN_SOURCE_META" \
   --arg next_batch_recommended_enhancement "$NEXT_BATCH_RECOMMENDED_ENHANCEMENT_META" \
   --argjson next_batch_slot "$NEXT_BATCH_SLOT_META_JSON" \
   --argjson next_batch_recommended_components "$NEXT_BATCH_RECOMMENDED_COMPONENTS_META_JSON" \
   --argjson selected_components "$SELECTED_COMPONENTS_JSON" \
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
       complexity_tier: $complexity_tier,
       selected_components: $selected_components,
       complexity_prompt_hint: $complexity_prompt_hint,
       story_summary: $story_summary,
       core_action: $core_action,
       twist: $twist,
       one_sentence: $one_sentence,
       family: $family,
       mechanic: $mechanic,
       input_style: $input_style,
       output_style: $output_style,
       audience_promise: $audience_promise,
       publish_hook: $publish_hook,
       engine: $engine,
       original_twist: $original_twist,
       original_one_sentence: $original_one_sentence,
       enhancement_source: $enhancement_source,
       enhancement_candidate_id: $enhancement_candidate_id,
       enhancement_adopted: ($enhancement_adopted == "true"),
       adopted_next_batch_complexity: ($adopted_next_batch_complexity == "true"),
       adopted_next_batch_components: ($adopted_next_batch_components == "true"),
       adopted_next_batch_enhancement: ($adopted_next_batch_enhancement == "true"),
       next_batch_plan_source: $next_batch_plan_source,
       next_batch_slot: $next_batch_slot,
       next_batch_recommended_components: $next_batch_recommended_components,
       next_batch_recommended_enhancement: ($next_batch_recommended_enhancement == "true"),
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
       title: $title,
       genre: $genre,
       family: $family,
       mechanic: $mechanic,
       input_style: $input_style,
       output_style: $output_style,
       audience_promise: $audience_promise,
       core_action: $core_action,
       twist: $twist,
       one_sentence: $one_sentence
     }]) | .[-20:])
   | .recent_meta[-1].complexity_tier = $complexity_tier
   | .recent_meta[-1].selected_components = $selected_components
   | .recent_meta[-1].complexity_prompt_hint = $complexity_prompt_hint
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

git add "$STATE_FILE" "$NOVELTY_SELECTION_FILE" 2>/dev/null || git add "$STATE_FILE"
git commit -m "state: ${DAY_LABEL} completed" >/dev/null || true

echo "  ✅ ${DAY_LABEL} 全工程完了"
