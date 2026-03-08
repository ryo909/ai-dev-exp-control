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
ARCHETYPE_PLAN_FILE="${ARCHETYPE_PLAN_FILE:-$CONTROL_DIR/plans/day009_015_archetype_plan_2026-03-08.json}"

DAY_NUM=${1:?'Usage: run_day.sh <day_number>'}
DAY_STR=$(printf '%03d' "$DAY_NUM")
DAY_LABEL="Day${DAY_STR}"
REPO_NAME="ai-dev-day-${DAY_STR}"
ENHANCED_CANDIDATES_FILE="$CONTROL_DIR/plans/candidates/day${DAY_STR}_enhanced_candidates.json"
NOVELTY_SELECTION_FILE="$CONTROL_DIR/plans/candidates/day${DAY_STR}_novelty_selection.json"
FORCE_REGENERATE="${FORCE_REGENERATE:-0}"
DIVERSITY_LOOKBACK_DAYS="${DIVERSITY_LOOKBACK_DAYS:-14}"
USE_ARCHETYPE_PLAN="${USE_ARCHETYPE_PLAN:-1}"

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
  INTERACTION_ARCHETYPE="${INTERACTION_ARCHETYPE:-single_shot_text_submit}"
  PAGE_ARCHETYPE="${PAGE_ARCHETYPE:-single_column_form}"
  OUTPUT_SHAPE="${OUTPUT_SHAPE:-single_text_block}"
  STATE_MODEL="${STATE_MODEL:-ephemeral_result_only}"
  CORE_LOOP="${CORE_LOOP:-input -> submit -> output}"
  COMPONENT_PACK="${COMPONENT_PACK:-single_form}"
  SCAFFOLD_ID="${SCAFFOLD_ID:-text_generator_scaffold}"
  SINGLE_SHOT_TEXT_GENERATOR="${SINGLE_SHOT_TEXT_GENERATOR:-true}"
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

  local generated_at selection_json override_id
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
    def infer_interaction($m):
      if (($m.interaction_archetype // "") | length) > 0 then $m.interaction_archetype
      else "single_shot_text_submit"
      end;
    def infer_page($m):
      if (($m.page_archetype // "") | length) > 0 then $m.page_archetype
      else "single_column_form"
      end;
    def infer_shape($m):
      if (($m.output_shape // "") | length) > 0 then $m.output_shape
      else "single_text_block"
      end;
    def infer_state_model($m):
      if (($m.state_model // "") | length) > 0 then $m.state_model
      else "ephemeral_result_only"
      end;
    def infer_component_pack($m):
      if (($m.component_pack // "") | length) > 0 then $m.component_pack
      else "single_form"
      end;
    def infer_scaffold($m):
      if (($m.scaffold_id // "") | length) > 0 then $m.scaffold_id
      else "text_generator_scaffold"
      end;
    def infer_single_shot($m):
      if ($m.single_shot_text_generator == true) then true
      elif ($m.single_shot_text_generator == false) then false
      else (infer_interaction($m) == "single_shot_text_submit")
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
            audience_promise: infer_audience($m),
            interaction_archetype: infer_interaction($m),
            page_archetype: infer_page($m),
            output_shape: infer_shape($m),
            state_model: infer_state_model($m),
            component_pack: infer_component_pack($m),
            scaffold_id: infer_scaffold($m),
            single_shot_text_generator: infer_single_shot($m)
          }
      ] as $recent
    | ([ $recent[] | select(.single_shot_text_generator == true) ] | length) as $single_shot_count
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
        | ([ $recent[] | select(.interaction_archetype == ($c.interaction_archetype // "single_shot_text_submit")) ] | length) as $interaction_hits
        | ([ $recent[] | select(.page_archetype == ($c.page_archetype // "single_column_form")) ] | length) as $page_hits
        | ([ $recent[] | select(.output_shape == ($c.output_shape // "single_text_block")) ] | length) as $shape_hits
        | ([ $recent[] | select(.state_model == ($c.state_model // "ephemeral_result_only")) ] | length) as $state_hits
        | ([ $recent[] | select(.component_pack == ($c.component_pack // "single_form")) ] | length) as $component_pack_hits
        | ([ $recent[] | select(.scaffold_id == ($c.scaffold_id // "text_generator_scaffold")) ] | length) as $scaffold_hits
        | (($c.single_shot_text_generator // false) == true) as $is_single_shot
        | [
            (if $title_hits > 0 then {code:"title_overlap_recent", count:$title_hits, penalty:130} else empty end),
            (if $family_hits > 0 then {code:"family_overlap_recent", count:$family_hits, penalty:(80 * $family_hits)} else empty end),
            (if $theme_hits > 0 then {code:"theme_overlap_recent", count:$theme_hits, penalty:(28 * $theme_hits)} else empty end),
            (if $mechanic_hits > 0 then {code:"mechanic_overlap_recent", count:$mechanic_hits, penalty:(35 * $mechanic_hits)} else empty end),
            (if $input_hits > 0 then {code:"input_overlap_recent", count:$input_hits, penalty:(35 * $input_hits)} else empty end),
            (if $output_hits > 0 then {code:"output_overlap_recent", count:$output_hits, penalty:(18 * $output_hits)} else empty end),
            (if $audience_hits > 0 then {code:"audience_overlap_recent", count:$audience_hits, penalty:(35 * $audience_hits)} else empty end),
            (if $interaction_hits > 0 then {code:"interaction_archetype_overlap", count:$interaction_hits, penalty:(95 * $interaction_hits)} else empty end),
            (if $page_hits > 0 then {code:"page_archetype_overlap", count:$page_hits, penalty:(85 * $page_hits)} else empty end),
            (if $shape_hits > 0 then {code:"output_shape_overlap", count:$shape_hits, penalty:(80 * $shape_hits)} else empty end),
            (if $state_hits > 0 then {code:"state_model_overlap", count:$state_hits, penalty:(72 * $state_hits)} else empty end),
            (if $component_pack_hits > 0 then {code:"component_pack_overlap", count:$component_pack_hits, penalty:(55 * $component_pack_hits)} else empty end),
            (if $scaffold_hits > 0 then {code:"scaffold_overlap", count:$scaffold_hits, penalty:(120 * $scaffold_hits)} else empty end),
            (if $core_hits > 1 then {code:"core_action_repeated", count:$core_hits, penalty:(12 * ($core_hits - 1))} else empty end),
            (if $genre_hits > 1 then {code:"genre_repeated", count:$genre_hits, penalty:(8 * ($genre_hits - 1))} else empty end),
            (if ($is_single_shot and $single_shot_count >= 2) then {code:"single_shot_cap_exceeded", count:$single_shot_count, penalty:400} else empty end),
            (if ($is_single_shot) then {code:"single_shot_discourage", count:1, penalty:40} else empty end)
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
            interaction_archetype: ($c.interaction_archetype // "single_shot_text_submit"),
            page_archetype: ($c.page_archetype // "single_column_form"),
            output_shape: ($c.output_shape // "single_text_block"),
            state_model: ($c.state_model // "ephemeral_result_only"),
            core_loop: ($c.core_loop // "input -> submit -> output"),
            component_pack: ($c.component_pack // "single_form"),
            scaffold_id: ($c.scaffold_id // "text_generator_scaffold"),
            single_shot_text_generator: ($c.single_shot_text_generator // false),
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
          note: "penalize similarity across concept + interaction/page/output/state/scaffold axes",
          reject_when_near_duplicate: true,
          single_shot_text_generator_max_per_batch: 2
        },
        recent_reference: $recent,
        recent_single_shot_count: $single_shot_count,
        selected: ($ranked[0] // null),
        ranked_candidates: $ranked,
        rejected_candidates: [ $ranked[] | select(.score < 60) | {id, title, score, penalties} ]
      }
  ')

  [ -n "$selection_json" ] || return 1
  if ! jq -e '.selected != null' >/dev/null 2>&1 <<<"$selection_json"; then
    return 1
  fi

  if [ "$USE_ARCHETYPE_PLAN" = "1" ] && [ -f "$ARCHETYPE_PLAN_FILE" ]; then
    override_id=$(jq -r --arg day "$DAY_STR" '.days[$day].candidate_id // empty' "$ARCHETYPE_PLAN_FILE" 2>/dev/null || true)
    if [ -n "$override_id" ]; then
      selection_json=$(jq --arg id "$override_id" '
        if ([.ranked_candidates[]?.id] | index($id)) != null then
          .selected = (.ranked_candidates[] | select(.id == $id))
          | .selection_mode = "archetype_override"
        else
          .selection_mode = "score_top"
          | .override_warning = ("override candidate not found: " + $id)
        end
      ' <<<"$selection_json")
    else
      selection_json=$(jq '.selection_mode = "score_top"' <<<"$selection_json")
    fi
  else
    selection_json=$(jq '.selection_mode = "score_top"' <<<"$selection_json")
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
  INTERACTION_ARCHETYPE=$(jq -r '.selected.interaction_archetype // empty' <<<"$selection_json")
  PAGE_ARCHETYPE=$(jq -r '.selected.page_archetype // empty' <<<"$selection_json")
  OUTPUT_SHAPE=$(jq -r '.selected.output_shape // empty' <<<"$selection_json")
  STATE_MODEL=$(jq -r '.selected.state_model // empty' <<<"$selection_json")
  CORE_LOOP=$(jq -r '.selected.core_loop // empty' <<<"$selection_json")
  COMPONENT_PACK=$(jq -r '.selected.component_pack // empty' <<<"$selection_json")
  SCAFFOLD_ID=$(jq -r '.selected.scaffold_id // empty' <<<"$selection_json")
  SINGLE_SHOT_TEXT_GENERATOR=$(jq -r '.selected.single_shot_text_generator // false | tostring' <<<"$selection_json")
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
  chmod -R u+w "$tmp_template" >/dev/null 2>&1 || true
  rm -rf "$tmp_template" >/dev/null 2>&1 || true
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
    recombine|combine) ACTION_LABEL="カードを引く" ;;
    navigate|triage) ACTION_LABEL="次へ進む" ;;
    score|optimize) ACTION_LABEL="再計算する" ;;
    flow|sequence) ACTION_LABEL="カードを動かす" ;;
    play|chain) ACTION_LABEL="スピンする" ;;
    *) ACTION_LABEL="実行する" ;;
  esac

  case "$INPUT_STYLE" in
    multi_select_tokens) INPUT_LABEL="素材トークン"; INPUT_PLACEHOLDER='UI / API / Habit / Team' ;;
    step_choices) INPUT_LABEL="ステップ回答"; INPUT_PLACEHOLDER='設問に沿って選択します' ;;
    item_with_scores) INPUT_LABEL="項目 + スコア"; INPUT_PLACEHOLDER=$'支払い遅延|impact5|urgency4\n通知漏れ|impact4|urgency3' ;;
    slider_weights_and_rows) INPUT_LABEL="重みと候補"; INPUT_PLACEHOLDER=$'速度|40\n品質|35\nコスト|25' ;;
    task_cards) INPUT_LABEL="タスクカード"; INPUT_PLACEHOLDER=$'調査\n実装\n検証' ;;
    card_creation) INPUT_LABEL="カード作成"; INPUT_PLACEHOLDER=$'カード名: API監視\nカード名: README更新' ;;
    preset_pool) INPUT_LABEL="ミッション候補"; INPUT_PLACEHOLDER='10分 / 1人 / 制約あり' ;;
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
    card_stack) OUTPUT_LABEL="カードスタック" ;;
    path_summary) OUTPUT_LABEL="判断パス" ;;
    response_flow) OUTPUT_LABEL="一次対応フロー" ;;
    quadrant_matrix) OUTPUT_LABEL="4象限マトリクス" ;;
    ranked_scores) OUTPUT_LABEL="重み付きランキング" ;;
    checklist_timeline) OUTPUT_LABEL="スロットチェックリスト" ;;
    lane_board) OUTPUT_LABEL="フローボード" ;;
    roulette_result) OUTPUT_LABEL="ラウンド結果" ;;
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

write_style_file() {
  case "$SCAFFOLD_ID" in
    card_deck_board)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:linear-gradient(135deg,#fff8e1,#fce4ec);margin:0;color:#2d1b4e}
#app{max-width:1100px;margin:0 auto;padding:24px}
.top{display:flex;justify-content:space-between;align-items:end;gap:16px;margin-bottom:20px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.panel{background:#fff;border-radius:16px;padding:16px;box-shadow:0 10px 24px rgba(93,38,140,.12)}
.tokens,.cards{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
.chip,.card{padding:8px 10px;border-radius:10px;background:#f3e5f5}
button{border:0;border-radius:10px;padding:10px 12px;background:#5e35b1;color:#fff;font-weight:600;cursor:pointer}
input{width:100%;padding:10px;border:1px solid #d1c4e9;border-radius:8px}
ul{padding-left:18px}
@media (max-width:800px){.grid{grid-template-columns:1fr}}
CSS
      ;;
    wizard_stepper)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:#f3f7ff;margin:0;color:#102a43}
#app{max-width:820px;margin:0 auto;padding:24px}
.wizard{background:#fff;border:1px solid #d9e2ec;border-radius:16px;padding:20px}
.step{display:inline-block;padding:6px 12px;border-radius:999px;background:#e3f2fd;font-weight:700}
.question{font-size:1.25rem;margin:14px 0}
.choices{display:grid;gap:10px}
.choice{display:flex;gap:10px;align-items:flex-start;padding:10px;border:1px solid #d9e2ec;border-radius:10px}
.actions{display:flex;justify-content:space-between;margin-top:16px}
button{border:0;border-radius:10px;padding:10px 14px;background:#0d47a1;color:#fff;font-weight:700;cursor:pointer}
pre{background:#102a43;color:#f0f4f8;padding:12px;border-radius:10px;white-space:pre-wrap}
CSS
      ;;
    matrix_mapper)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:#fffbe6;margin:0;color:#3e2723}
#app{max-width:1100px;margin:0 auto;padding:24px}
.layout{display:grid;grid-template-columns:320px 1fr;gap:16px}
.panel{background:#fff;border:2px solid #ffe082;border-radius:14px;padding:14px}
.matrix{display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;gap:10px;min-height:420px}
.quad{border-radius:12px;padding:10px;background:#fff8e1;border:1px solid #ffcc80}
.quad h3{margin:0 0 8px 0;font-size:.95rem}
button{border:0;border-radius:10px;padding:10px 12px;background:#ef6c00;color:#fff;font-weight:700;cursor:pointer}
input,select{width:100%;padding:8px;margin-bottom:8px;border:1px solid #ffcc80;border-radius:8px}
@media (max-width:900px){.layout{grid-template-columns:1fr}}
CSS
      ;;
    weighted_calculator)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:#0f172a;margin:0;color:#e2e8f0}
#app{max-width:1100px;margin:0 auto;padding:24px}
.dash{display:grid;grid-template-columns:340px 1fr;gap:16px}
.panel{background:#111827;border:1px solid #1f2937;border-radius:14px;padding:16px}
label{display:block;margin-top:8px}
input,button{width:100%;padding:10px;border-radius:8px;border:1px solid #334155;background:#0b1220;color:#e2e8f0}
button{background:#2563eb;border:0;font-weight:700;cursor:pointer}
table{width:100%;border-collapse:collapse;margin-top:10px}
th,td{border-bottom:1px solid #334155;padding:8px;text-align:left}
.meter{font-size:.9rem;color:#93c5fd}
@media (max-width:900px){.dash{grid-template-columns:1fr}}
CSS
      ;;
    slot_checklist_planner)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:#f0fff4;margin:0;color:#1b4332}
#app{max-width:1100px;margin:0 auto;padding:24px}
.planner{display:grid;grid-template-columns:300px 1fr;gap:16px}
.panel{background:#fff;border:1px solid #b7e4c7;border-radius:14px;padding:14px}
.slots{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.slot{background:#f1faee;border-radius:12px;padding:10px;min-height:260px}
.task{display:flex;gap:8px;align-items:center;padding:6px 0}
input,select,button{width:100%;padding:9px;border:1px solid #95d5b2;border-radius:8px}
button{background:#2d6a4f;color:#fff;border:0;font-weight:700;cursor:pointer}
@media (max-width:900px){.planner{grid-template-columns:1fr}.slots{grid-template-columns:1fr}}
CSS
      ;;
    flow_board)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:#f5f3ff;margin:0;color:#312e81}
#app{max-width:1200px;margin:0 auto;padding:24px}
.toolbar{display:grid;grid-template-columns:1fr 180px;gap:10px;margin-bottom:12px}
input,button{padding:10px;border-radius:8px;border:1px solid #c4b5fd}
button{background:#7c3aed;color:#fff;border:0;font-weight:700;cursor:pointer}
.board{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.lane{background:#fff;border:1px solid #ddd6fe;border-radius:12px;padding:10px;min-height:340px}
.card{background:#ede9fe;border-radius:10px;padding:8px;margin:8px 0}
.card button{width:auto;padding:6px 8px;font-size:.82rem}
@media (max-width:900px){.board{grid-template-columns:1fr}}
CSS
      ;;
    roulette_game)
      cat > src/style.css <<'CSS'
body{font-family:"Inter","Noto Sans JP",sans-serif;background:radial-gradient(circle at top,#1f2937,#020617);margin:0;color:#f8fafc}
#app{max-width:880px;margin:0 auto;padding:24px}
.game{background:#0f172a;border:1px solid #334155;border-radius:16px;padding:18px}
.wheel{font-size:2rem;text-align:center;padding:18px;border-radius:999px;background:#1e293b;margin:10px auto;width:220px;height:220px;display:flex;align-items:center;justify-content:center}
.controls{display:grid;grid-template-columns:1fr 1fr;gap:10px}
input,button{padding:10px;border-radius:8px;border:1px solid #475569;background:#111827;color:#f8fafc}
button{background:#f59e0b;color:#111827;border:0;font-weight:800;cursor:pointer}
.score{display:flex;gap:10px;justify-content:space-between;margin-top:12px}
ul{min-height:120px}
CSS
      ;;
    *)
      cp "$CONTROL_DIR/../ai-dev-exp-template/src/style.css" src/style.css 2>/dev/null || true
      ;;
  esac
}

write_index_file() {
  case "$SCAFFOLD_ID" in
    card_deck_board)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><div class="top"><div><div>${DAY_LABEL}</div><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p></div><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></div>
<div class="grid"><section class="panel"><h2>Token Pool</h2><input id="tokenInput" placeholder="${INPUT_PLACEHOLDER_HTML}"><button id="addTokenBtn">追加</button><div id="tokenList" class="tokens"></div><hr><button id="drawBtn">3枚引く</button><button id="lockBtn">ロック切替</button></section><section class="panel"><h2>Drawn Cards</h2><div id="cardStack" class="cards"></div><h3>History</h3><ul id="historyList"></ul></section></div></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    wizard_stepper)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="wizard"><div id="stepBadge" class="step">Step 1/3</div><div id="questionText" class="question"></div><div id="choiceGroup" class="choices"></div><div class="actions"><button id="prevStepBtn">戻る</button><button id="nextStepBtn">次へ</button></div><h3>Decision Path</h3><pre id="wizardSummary"></pre></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    matrix_mapper)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="layout"><section class="panel"><h2>Add Item</h2><input id="matrixItemName" placeholder="項目名"><label>Impact <input id="impactRange" type="range" min="1" max="5" value="3"></label><label>Urgency <input id="urgencyRange" type="range" min="1" max="5" value="3"></label><button id="addMatrixItemBtn">配置する</button></section><section class="matrix"><div class="quad"><h3>High Impact / High Urgency</h3><ul id="qHH"></ul></div><div class="quad"><h3>High Impact / Low Urgency</h3><ul id="qHL"></ul></div><div class="quad"><h3>Low Impact / High Urgency</h3><ul id="qLH"></ul></div><div class="quad"><h3>Low Impact / Low Urgency</h3><ul id="qLL"></ul></div></section></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    weighted_calculator)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="dash"><section class="panel"><h2>Weights</h2><label>Speed <input id="wSpeed" type="range" min="0" max="100" value="40"></label><label>Quality <input id="wQuality" type="range" min="0" max="100" value="35"></label><label>Cost <input id="wCost" type="range" min="0" max="100" value="25"></label><p class="meter" id="weightMeter"></p></section><section class="panel"><h2>Options</h2><input id="optionName" placeholder="候補名"><input id="optionSpeed" type="number" min="1" max="5" placeholder="Speed 1-5"><input id="optionQuality" type="number" min="1" max="5" placeholder="Quality 1-5"><input id="optionCost" type="number" min="1" max="5" placeholder="Cost 1-5"><button id="addOptionBtn">候補追加</button><button id="recalcBtn">再計算</button><table><thead><tr><th>Option</th><th>Score</th></tr></thead><tbody id="scoreTable"></tbody></table></section></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    slot_checklist_planner)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="planner"><section class="panel"><h2>Add Task</h2><input id="taskInput" placeholder="タスク名"><select id="slotSelect"><option value="morning">Morning</option><option value="afternoon">Afternoon</option><option value="evening">Evening</option></select><button id="addTaskBtn">追加</button><button id="carryBtn">未完了を次枠へ繰越</button></section><section class="slots"><div class="slot"><h3>Morning</h3><div id="slotMorning"></div></div><div class="slot"><h3>Afternoon</h3><div id="slotAfternoon"></div></div><div class="slot"><h3>Evening</h3><div id="slotEvening"></div></div></section></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    flow_board)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="toolbar"><input id="cardTitleInput" placeholder="新しいカード"><button id="addFlowCardBtn">カード追加</button></div><div class="board"><section class="lane"><h3>Todo</h3><div id="laneTodo"></div></section><section class="lane"><h3>Doing</h3><div id="laneDoing"></div></section><section class="lane"><h3>Done</h3><div id="laneDone"></div></section></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    roulette_game)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><div class="game"><input id="missionInput" placeholder="${INPUT_PLACEHOLDER_HTML}"><button id="addMissionBtn">ミッション追加</button><div class="wheel" id="wheelFace">SPIN</div><div class="controls"><button id="spinBtn">スピン</button><button id="clearRoundBtn">履歴クリア</button></div><div class="score"><strong>Score: <span id="scoreValue">0</span></strong><strong>Round: <span id="roundValue">0</span></strong></div><h3>Pool</h3><ul id="missionPool"></ul><h3>History</h3><ul id="roundHistory"></ul></div><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
    *)
      cat > index.html <<HTML
<!DOCTYPE html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>${DAY_LABEL} — ${TITLE}</title><meta name="description" content="${ONE_SENTENCE}"><link rel="stylesheet" href="/src/style.css"></head>
<body><div id="app"><h1>${TITLE}</h1><p>${ONE_SENTENCE}</p><textarea id="toolInput" rows="6" placeholder="${INPUT_PLACEHOLDER_HTML}"></textarea><button id="actionBtn">${ACTION_LABEL}</button><pre id="toolOutput"></pre><p><a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a></p></div><script type="module" src="/src/main.js"></script></body></html>
HTML
      ;;
  esac
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
    --arg interaction_archetype "$INTERACTION_ARCHETYPE" \
    --arg page_archetype "$PAGE_ARCHETYPE" \
    --arg output_shape "$OUTPUT_SHAPE" \
    --arg state_model "$STATE_MODEL" \
    --arg core_loop "$CORE_LOOP" \
    --arg component_pack "$COMPONENT_PACK" \
    --arg scaffold_id "$SCAFFOLD_ID" \
    --arg single_shot "$SINGLE_SHOT_TEXT_GENERATOR" \
    '{day:$day,title:$title,one_sentence:$one_sentence,core_action:$core_action,family:$family,mechanic:$mechanic,input_style:$input_style,output_style:$output_style,audience_promise:$audience_promise,publish_hook:$publish_hook,engine:$engine,interaction_archetype:$interaction_archetype,page_archetype:$page_archetype,output_shape:$output_shape,state_model:$state_model,core_loop:$core_loop,component_pack:$component_pack,scaffold_id:$scaffold_id,single_shot_text_generator:($single_shot=="true")}')

  {
    echo "import './style.css';"
    printf 'const PROFILE = %s;\n' "$profile_json"
    cat <<'JS'
const byId = (id) => document.getElementById(id);
const state = {
  tokens: ['UI', 'API', 'Habit', 'Team'],
  lock: false,
  history: [],
  wizardStep: 0,
  wizardAnswers: {},
  matrix: { HH: [], HL: [], LH: [], LL: [] },
  options: [],
  slots: { morning: [], afternoon: [], evening: [] },
  board: { todo: [], doing: [], done: [] },
  missions: ['5分で試す', '2案比較する', '短文で説明する'],
  score: 0,
  round: 0
};

boot();

function boot() {
  switch (PROFILE.scaffold_id) {
    case 'card_deck_board': return setupCardDeck();
    case 'wizard_stepper': return setupWizard();
    case 'matrix_mapper': return setupMatrix();
    case 'weighted_calculator': return setupWeightedCalc();
    case 'slot_checklist_planner': return setupSlotPlanner();
    case 'flow_board': return setupFlowBoard();
    case 'roulette_game': return setupRoulette();
    default: return setupFallback();
  }
}

function setupCardDeck() {
  const tokenInput = byId('tokenInput');
  const tokenList = byId('tokenList');
  const cardStack = byId('cardStack');
  const historyList = byId('historyList');
  byId('addTokenBtn').addEventListener('click', () => {
    const v = (tokenInput.value || '').trim();
    if (!v) return;
    state.tokens.push(v);
    tokenInput.value = '';
    renderTokenPool(tokenList);
  });
  byId('drawBtn').addEventListener('click', () => {
    if (state.lock) return;
    const picks = shuffle([...state.tokens]).slice(0, Math.min(3, state.tokens.length));
    cardStack.innerHTML = picks.map((x) => `<div class="card">${escapeHtml(x)}</div>`).join('');
    state.history.unshift(picks.join(' × '));
    state.history = state.history.slice(0, 12);
    historyList.innerHTML = state.history.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  });
  byId('lockBtn').addEventListener('click', () => { state.lock = !state.lock; });
  renderTokenPool(tokenList);
}

function renderTokenPool(el) {
  el.innerHTML = state.tokens.map((x) => `<span class="chip">${escapeHtml(x)}</span>`).join('');
}

function setupWizard() {
  const questions = [
    { key: 'speed', q: '最優先はどれ?', c: ['速度', '品質', 'コスト'] },
    { key: 'risk', q: '許容できるリスクは?', c: ['低い', '中くらい', '高い'] },
    { key: 'ownership', q: '主導者は?', c: ['自分', 'チーム', '外部'] }
  ];
  const stepBadge = byId('stepBadge');
  const questionText = byId('questionText');
  const choiceGroup = byId('choiceGroup');
  const summary = byId('wizardSummary');
  byId('prevStepBtn').addEventListener('click', () => { state.wizardStep = Math.max(0, state.wizardStep - 1); renderStep(); });
  byId('nextStepBtn').addEventListener('click', () => {
    const cur = questions[state.wizardStep];
    const selected = document.querySelector('input[name="wizardChoice"]:checked');
    if (selected) state.wizardAnswers[cur.key] = selected.value;
    state.wizardStep = Math.min(questions.length - 1, state.wizardStep + 1);
    renderStep();
  });
  function renderStep() {
    const cur = questions[state.wizardStep];
    stepBadge.textContent = `Step ${state.wizardStep + 1}/${questions.length}`;
    questionText.textContent = cur.q;
    choiceGroup.innerHTML = cur.c.map((x) => `<label class="choice"><input type="radio" name="wizardChoice" value="${escapeHtml(x)}" ${state.wizardAnswers[cur.key]===x?'checked':''}>${escapeHtml(x)}</label>`).join('');
    summary.textContent = Object.entries(state.wizardAnswers).map(([k,v]) => `${k}: ${v}`).join('\n') || 'まだ回答がありません';
  }
  renderStep();
}

function setupMatrix() {
  const inputName = byId('matrixItemName');
  const impact = byId('impactRange');
  const urgency = byId('urgencyRange');
  byId('addMatrixItemBtn').addEventListener('click', () => {
    const name = (inputName.value || '').trim();
    if (!name) return;
    const i = Number(impact.value);
    const u = Number(urgency.value);
    const key = i >= 3 && u >= 3 ? 'HH' : i >= 3 ? 'HL' : u >= 3 ? 'LH' : 'LL';
    state.matrix[key].push(name);
    inputName.value = '';
    renderMatrix();
  });
  renderMatrix();
}

function renderMatrix() {
  byId('qHH').innerHTML = state.matrix.HH.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  byId('qHL').innerHTML = state.matrix.HL.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  byId('qLH').innerHTML = state.matrix.LH.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  byId('qLL').innerHTML = state.matrix.LL.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
}

function setupWeightedCalc() {
  const meter = byId('weightMeter');
  const scoreTable = byId('scoreTable');
  const recalc = () => {
    const ws = Number(byId('wSpeed').value), wq = Number(byId('wQuality').value), wc = Number(byId('wCost').value);
    const sum = ws + wq + wc || 1;
    meter.textContent = `weight ratio => speed:${ws} quality:${wq} cost:${wc}`;
    const rows = state.options.map((o) => {
      const score = (o.speed * ws + o.quality * wq + (6 - o.cost) * wc) / sum;
      return { name: o.name, score: score.toFixed(2) };
    }).sort((a,b) => Number(b.score) - Number(a.score));
    scoreTable.innerHTML = rows.map((r) => `<tr><td>${escapeHtml(r.name)}</td><td>${r.score}</td></tr>`).join('');
  };
  ['wSpeed','wQuality','wCost'].forEach((id) => byId(id).addEventListener('input', recalc));
  byId('addOptionBtn').addEventListener('click', () => {
    const name = (byId('optionName').value || '').trim();
    const speed = Number(byId('optionSpeed').value || 0);
    const quality = Number(byId('optionQuality').value || 0);
    const cost = Number(byId('optionCost').value || 0);
    if (!name || !speed || !quality || !cost) return;
    state.options.push({ name, speed, quality, cost });
    byId('optionName').value = '';
    byId('optionSpeed').value = '';
    byId('optionQuality').value = '';
    byId('optionCost').value = '';
    recalc();
  });
  byId('recalcBtn').addEventListener('click', recalc);
  recalc();
}

function setupSlotPlanner() {
  byId('addTaskBtn').addEventListener('click', () => {
    const task = (byId('taskInput').value || '').trim();
    const slot = byId('slotSelect').value;
    if (!task) return;
    state.slots[slot].push({ text: task, done: false });
    byId('taskInput').value = '';
    renderSlots();
  });
  byId('carryBtn').addEventListener('click', () => {
    carry('morning', 'afternoon');
    carry('afternoon', 'evening');
    renderSlots();
  });
  renderSlots();
}

function carry(from, to) {
  const stay = [];
  state.slots[from].forEach((t) => {
    if (t.done) stay.push(t);
    else state.slots[to].push({ text: t.text, done: false });
  });
  state.slots[from] = stay;
}

function renderSlots() {
  renderSlot('morning', byId('slotMorning'));
  renderSlot('afternoon', byId('slotAfternoon'));
  renderSlot('evening', byId('slotEvening'));
}

function renderSlot(key, el) {
  el.innerHTML = state.slots[key].map((t, i) => `<label class="task"><input type="checkbox" ${t.done?'checked':''} data-slot="${key}" data-idx="${i}">${escapeHtml(t.text)}</label>`).join('');
  el.querySelectorAll('input[type="checkbox"]').forEach((box) => {
    box.addEventListener('change', (e) => {
      const slot = e.target.dataset.slot;
      const idx = Number(e.target.dataset.idx);
      state.slots[slot][idx].done = e.target.checked;
    });
  });
}

function setupFlowBoard() {
  byId('addFlowCardBtn').addEventListener('click', () => {
    const title = (byId('cardTitleInput').value || '').trim();
    if (!title) return;
    state.board.todo.push({ id: Date.now(), title });
    byId('cardTitleInput').value = '';
    renderBoard();
  });
  renderBoard();
}

function renderBoard() {
  renderLane('todo', byId('laneTodo'), 'doing');
  renderLane('doing', byId('laneDoing'), 'done');
  renderLane('done', byId('laneDone'), null);
}

function renderLane(key, el, next) {
  el.innerHTML = state.board[key].map((c, i) => `<div class="card"><div>${escapeHtml(c.title)}</div>${next ? `<button data-lane="${key}" data-idx="${i}" data-next="${next}">→ ${next}</button>` : ''}</div>`).join('');
  el.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      const lane = btn.dataset.lane;
      const idx = Number(btn.dataset.idx);
      const to = btn.dataset.next;
      const [card] = state.board[lane].splice(idx, 1);
      state.board[to].push(card);
      renderBoard();
    });
  });
}

function setupRoulette() {
  const wheel = byId('wheelFace');
  const score = byId('scoreValue');
  const round = byId('roundValue');
  const missionPool = byId('missionPool');
  const history = byId('roundHistory');

  byId('addMissionBtn').addEventListener('click', () => {
    const m = (byId('missionInput').value || '').trim();
    if (!m) return;
    state.missions.push(m);
    byId('missionInput').value = '';
    renderPool();
  });
  byId('spinBtn').addEventListener('click', () => {
    if (state.missions.length === 0) return;
    const picked = state.missions[Math.floor(Math.random() * state.missions.length)];
    wheel.textContent = picked;
    state.round += 1;
    state.score += 10;
    state.history.unshift(`R${state.round}: ${picked}`);
    state.history = state.history.slice(0, 12);
    round.textContent = String(state.round);
    score.textContent = String(state.score);
    history.innerHTML = state.history.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  });
  byId('clearRoundBtn').addEventListener('click', () => {
    state.round = 0; state.score = 0; state.history = []; wheel.textContent = 'SPIN';
    round.textContent = '0'; score.textContent = '0'; history.innerHTML = '';
  });
  function renderPool() {
    missionPool.innerHTML = state.missions.map((x) => `<li>${escapeHtml(x)}</li>`).join('');
  }
  renderPool();
}

function setupFallback() {
  const input = byId('toolInput');
  const output = byId('toolOutput');
  const btn = byId('actionBtn');
  if (!input || !output || !btn) return;
  btn.addEventListener('click', () => {
    const txt = (input.value || '').trim();
    output.textContent = txt ? `chars=${txt.length}` : '入力してください';
  });
}

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function escapeHtml(v) {
  return String(v).replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
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
  --arg interaction_archetype "$INTERACTION_ARCHETYPE" \
  --arg page_archetype "$PAGE_ARCHETYPE" \
  --arg output_shape "$OUTPUT_SHAPE" \
  --arg state_model "$STATE_MODEL" \
  --arg core_loop "$CORE_LOOP" \
  --arg component_pack "$COMPONENT_PACK" \
  --arg scaffold_id "$SCAFFOLD_ID" \
  --arg single_shot_text_generator "$SINGLE_SHOT_TEXT_GENERATOR" \
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
    interaction_archetype: $interaction_archetype,
    page_archetype: $page_archetype,
    output_shape: $output_shape,
    state_model: $state_model,
    core_loop: $core_loop,
    component_pack: $component_pack,
    scaffold_id: $scaffold_id,
    single_shot_text_generator: ($single_shot_text_generator == "true"),
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
write_style_file
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
git add meta.json README.md STORY.md index.html src/main.js src/style.css public/media 2>/dev/null \
  || git add meta.json README.md STORY.md index.html src/main.js src/style.css
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
   --arg interaction_archetype "$INTERACTION_ARCHETYPE" \
   --arg page_archetype "$PAGE_ARCHETYPE" \
   --arg output_shape "$OUTPUT_SHAPE" \
   --arg state_model "$STATE_MODEL" \
   --arg core_loop "$CORE_LOOP" \
   --arg component_pack "$COMPONENT_PACK" \
   --arg scaffold_id "$SCAFFOLD_ID" \
   --arg single_shot_text_generator "$SINGLE_SHOT_TEXT_GENERATOR" \
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
       interaction_archetype: $interaction_archetype,
       page_archetype: $page_archetype,
       output_shape: $output_shape,
       state_model: $state_model,
       core_loop: $core_loop,
       component_pack: $component_pack,
       scaffold_id: $scaffold_id,
       single_shot_text_generator: ($single_shot_text_generator == "true"),
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
   | .next_day = ([((.next_day // 1) | tonumber), (($day | tonumber) + 1)] | max)
   | .recent_meta = ((.recent_meta + [{
       day: $day,
       title: $title,
       genre: $genre,
       family: $family,
       mechanic: $mechanic,
       input_style: $input_style,
       output_style: $output_style,
       audience_promise: $audience_promise,
       interaction_archetype: $interaction_archetype,
       page_archetype: $page_archetype,
       output_shape: $output_shape,
       state_model: $state_model,
       component_pack: $component_pack,
       scaffold_id: $scaffold_id,
       single_shot_text_generator: ($single_shot_text_generator == "true"),
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
