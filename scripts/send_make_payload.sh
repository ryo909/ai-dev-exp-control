#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"
ENV_FILE="$CONTROL_DIR/.env.local"
REPORT_DIR="$CONTROL_DIR/reports/publish"
SCHEDULE_POLICY_FILE="$CONTROL_DIR/system/publish_schedule_policy.json"
WEEKDAY_KEYS=(mon tue wed thu fri sat sun)

DATE=""
DAYS_CSV=""
PREVIEW=0
FORCE=0
WEBHOOK_ONLY=0
BATCH_ID=""
PLATFORMS_CSV="x"

usage() {
  cat <<'USAGE'
Usage:
  scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only [--platforms x,youtube] [--preview] [--force] [--batch-id ID]

Rules:
  - --webhook-only は必須
  - 既に last_make_webhook.posted_targets（fallback: posted_days×target_platforms）に含まれる day-platform を送る場合は --force 必須
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --date)
      DATE="${2:-}"
      shift 2
      ;;
    --days)
      DAYS_CSV="${2:-}"
      shift 2
      ;;
    --preview)
      PREVIEW=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --webhook-only)
      WEBHOOK_ONLY=1
      shift
      ;;
    --batch-id)
      BATCH_ID="${2:-}"
      shift 2
      ;;
    --platforms)
      PLATFORMS_CSV="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$DATE" ] || [ -z "$DAYS_CSV" ] || [ "$WEBHOOK_ONLY" -ne 1 ]; then
  usage
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ missing: .env.local" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

MAKE_WEBHOOK_URL="${MAKE_WEBHOOK_URL:-}"
MAKE_WEBHOOK_APIKEY="${MAKE_WEBHOOK_APIKEY:-}"
if [ -z "$MAKE_WEBHOOK_URL" ] || [ -z "$MAKE_WEBHOOK_APIKEY" ]; then
  echo "❌ MAKE_WEBHOOK_URL / MAKE_WEBHOOK_APIKEY missing" >&2
  exit 1
fi

if [ -f "$SCHEDULE_POLICY_FILE" ]; then
  POLICY_START_OFFSET=$(jq -r '.start_offset_days // 1' "$SCHEDULE_POLICY_FILE" 2>/dev/null || echo "1")
  POLICY_TIMEZONE=$(jq -r '.timezone // "Asia/Tokyo"' "$SCHEDULE_POLICY_FILE" 2>/dev/null || echo "Asia/Tokyo")
else
  POLICY_START_OFFSET="1"
  POLICY_TIMEZONE="Asia/Tokyo"
fi
SCHEDULE_TIME="${MAKE_SCHEDULE_TIME:-}"
SCHEDULE_START_OFFSET_DAYS="${MAKE_SCHEDULE_START_OFFSET_DAYS:-$POLICY_START_OFFSET}"
SCHEDULE_TIMEZONE="${MAKE_SCHEDULE_TIMEZONE:-$POLICY_TIMEZONE}"
if [[ ! "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  SCHEDULE_TIME="21:00"
fi
if [[ ! "$SCHEDULE_START_OFFSET_DAYS" =~ ^-?[0-9]+$ ]]; then
  echo "❌ invalid MAKE_SCHEDULE_START_OFFSET_DAYS: $SCHEDULE_START_OFFSET_DAYS" >&2
  exit 1
fi

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

DAYS_JSON=$(jq -nc --arg csv "$DAYS_CSV" '
  ($csv
   | split(",")
   | map(gsub("[^0-9]"; ""))
   | map(select(length > 0))
   | map((. | tonumber) as $n | ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end)
  ) | unique | sort
')

PLATFORMS_JSON=$(jq -nc --arg csv "$PLATFORMS_CSV" '
  ($csv
   | ascii_downcase
   | split(",")
   | map(gsub("[^a-z]"; ""))
   | map(select(length > 0))
   | map(if . == "twitter" then "x" else . end)
   | map(select(. == "x" or . == "youtube"))
  ) | unique | sort
')

REQ_COUNT=$(jq 'length' <<<"$DAYS_JSON")
if [ "$REQ_COUNT" -eq 0 ]; then
  echo "❌ days parse failed: $DAYS_CSV" >&2
  exit 1
fi
PLATFORM_COUNT=$(jq 'length' <<<"$PLATFORMS_JSON")
if [ "$PLATFORM_COUNT" -eq 0 ]; then
  echo "❌ platforms parse failed: $PLATFORMS_CSV" >&2
  exit 1
fi

BASE_X_POSTS_JSON=$(jq -c --argjson days "$DAYS_JSON" '
  [ $days[] as $d
    | .days[$d] as $entry
    | select($entry)
    | {
        day: $d,
        platform: "x",
        text: ($entry.post_texts.standard // $entry.post_texts.compact // $entry.post_texts.minimal // "")
      }
    | select(.text != "")
  ] | sort_by(.day)
' "$STATE_FILE")

tmp_posts_file=$(mktemp)
idx=0
while IFS= read -r row; do
  [ -z "$row" ] && continue
  due_at=$(build_due_at "$DATE" "$idx" "x" "$SCHEDULE_START_OFFSET_DAYS" "$SCHEDULE_TIME")
  jq -nc --argjson row "$row" --arg dueAt "$due_at" '$row + {dueAt:$dueAt}' >> "$tmp_posts_file"
  idx=$((idx + 1))
done < <(jq -c '.[]' <<<"$BASE_X_POSTS_JSON")
STATE_X_POSTS_JSON=$(jq -cs 'sort_by(.day)' "$tmp_posts_file")
rm -f "$tmp_posts_file"

X_SOURCE="state_fallback"
MAKE_PAYLOAD_FILE="$CONTROL_DIR/exports/launch/make_payload_${DATE}.json"
if [ -f "$MAKE_PAYLOAD_FILE" ]; then
  FILE_X_POSTS_JSON=$(jq -c --argjson days "$DAYS_JSON" '
    (.x_items // .publish_items // []) as $items
    | if ($items | type) != "array" then []
      else
        [ $items[]
          | .platform = ((.platform // "x") | ascii_downcase)
          | .day = (
              (.day | tostring | gsub("[^0-9]"; "")) as $d
              | ($d | tonumber?) as $n
              | if $n == null then "" else ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end end
            )
          | select(.platform == "x")
          | (.day) as $day
          | select($days | index($day))
          | select((.text // "") != "")
          | select((.dueAt // "") != "")
          | {day, platform, text, dueAt}
        ] | sort_by(.day)
      end
  ' "$MAKE_PAYLOAD_FILE")
  FILE_X_COUNT=$(jq 'length' <<<"$FILE_X_POSTS_JSON")
  if [ "$FILE_X_COUNT" -gt 0 ]; then
    STATE_X_POSTS_JSON="$FILE_X_POSTS_JSON"
    X_SOURCE="make_payload"
  fi
fi

X_COUNT=$(jq 'length' <<<"$STATE_X_POSTS_JSON")
if jq -e 'index("x")' <<<"$PLATFORMS_JSON" >/dev/null 2>&1 && [ "$X_COUNT" -ne "$REQ_COUNT" ]; then
  echo "❌ some days missing x post payload (requested=$REQ_COUNT, ready=$X_COUNT)" >&2
  echo "requested: $(jq -r 'join(",")' <<<"$DAYS_JSON")" >&2
  echo "ready: $(jq -r '[.[].day] | join(",")' <<<"$STATE_X_POSTS_JSON")" >&2
  exit 1
fi

YOUTUBE_POSTS_JSON="[]"
YOUTUBE_SOURCE="none"
YOUTUBE_PREVIEW_JSON="[]"
YOUTUBE_MISSING_VIDEO_COUNT=0
if jq -e 'index("youtube")' <<<"$PLATFORMS_JSON" >/dev/null 2>&1; then
  if [ -f "$MAKE_PAYLOAD_FILE" ]; then
    YOUTUBE_PREVIEW_JSON=$(jq -c --argjson days "$DAYS_JSON" '
      def norm_day:
        (.day | tostring | gsub("[^0-9]"; "")) as $d
        | ($d | tonumber?) as $n
        | if $n == null then "" else ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end end;
      [ (.youtube_items // .publish_items // [])[]?
        | .platform = ((.platform // "youtube") | ascii_downcase)
        | .day = norm_day
        | select(.platform == "youtube")
        | (.day) as $day
        | select($days | index($day))
        | .missing_fields = ((.missing_fields // []) | map(tostring))
        | .readiness = (
            if (.readiness // "") != "" then .readiness
            elif ((.videoUrl // "") == "") then "pending_asset"
            elif ((.title // "") == "" or (.dueAt // "") == "") then "blocked"
            else "ready"
            end
          )
        | {
            day,
            platform,
            title: (.title // ""),
            dueAt: (.dueAt // ""),
            videoUrl: (.videoUrl // ""),
            readiness,
            missing_fields,
            video_source: (.video_source // "")
          }
      ] | sort_by(.day)
    ' "$MAKE_PAYLOAD_FILE")
    YOUTUBE_MISSING_VIDEO_COUNT=$(jq '[.[] | select(.readiness=="pending_asset")] | length' <<<"$YOUTUBE_PREVIEW_JSON")
    YOUTUBE_POSTS_JSON=$(jq -c --argjson days "$DAYS_JSON" '
      (.youtube_items // .publish_items // []) as $items
      | if ($items | type) != "array" then []
        else
          [ $items[]
            | .platform = ((.platform // "youtube") | ascii_downcase)
            | .day = (
                (.day | tostring | gsub("[^0-9]"; "")) as $d
                | ($d | tonumber?) as $n
                | if $n == null then "" else ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end end
              )
            | select(.platform == "youtube")
            | (.day) as $day
            | select($days | index($day))
            | {
                day,
                platform,
                title: (.title // ""),
                description: (.description // ""),
                videoUrl: (.videoUrl // ""),
                thumbnailUrl: (.thumbnailUrl // ""),
                dueAt: (.dueAt // ""),
                readiness: (.readiness // ""),
                missing_fields: (.missing_fields // []),
                privacy: (.privacy // "public"),
                madeForKids: (.madeForKids // false),
                notifySubscribers: (.notifySubscribers // true)
              }
            | select(.title != "")
            | select(.videoUrl != "")
            | select(.dueAt != "")
            | select((.readiness // "ready") == "ready")
          ] | sort_by(.day)
        end
    ' "$MAKE_PAYLOAD_FILE")
    if [ "$(jq 'length' <<<"$YOUTUBE_POSTS_JSON")" -gt 0 ]; then
      YOUTUBE_SOURCE="make_payload"
    fi
  fi
fi

POSTS_JSON=$(jq -nc --argjson x "$STATE_X_POSTS_JSON" --argjson y "$YOUTUBE_POSTS_JSON" --argjson platforms "$PLATFORMS_JSON" '
  (if ($platforms | index("x")) then $x else [] end)
  + (if ($platforms | index("youtube")) then $y else [] end)
  | sort_by(.day, .platform)
')

X_READY_COUNT=$(jq '[.[] | select(.platform=="x")] | length' <<<"$STATE_X_POSTS_JSON")
YOUTUBE_READY_COUNT=$(jq '[.[] | select(.readiness=="ready")] | length' <<<"$YOUTUBE_PREVIEW_JSON")
YOUTUBE_PENDING_ASSET_COUNT=$(jq '[.[] | select(.readiness=="pending_asset")] | length' <<<"$YOUTUBE_PREVIEW_JSON")
YOUTUBE_BLOCKED_COUNT=$(jq '[.[] | select(.readiness=="blocked")] | length' <<<"$YOUTUBE_PREVIEW_JSON")
YOUTUBE_INVALID_COUNT=$(jq '[.[] | select(.readiness=="invalid")] | length' <<<"$YOUTUBE_PREVIEW_JSON")

POST_COUNT=$(jq 'length' <<<"$POSTS_JSON")
if [ "$POST_COUNT" -eq 0 ]; then
  echo "❌ no posts resolved for target days/platforms" >&2
  exit 1
fi

REQUEST_TARGETS_JSON=$(jq -c '
  [
    .[]
    | {
        day: (.day | tostring),
        platform: ((.platform // "x") | ascii_downcase),
        key: ((.day | tostring) + "-" + ((.platform // "x") | ascii_downcase))
      }
  ] | unique_by(.key) | sort_by(.day, .platform)
' <<<"$POSTS_JSON")

LAST_POSTED_TARGET_KEYS=$(jq -c '
  def norm_day:
    (tostring | gsub("[^0-9]"; "")) as $d
    | ($d | tonumber?) as $n
    | if $n == null then "" else ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end end;
  def norm_platform:
    (tostring | ascii_downcase | if . == "twitter" then "x" else . end);
  (.last_make_webhook // {}) as $w
  | if (($w.posted_targets // null) | type) == "array" and (($w.posted_targets | length) > 0) then
      [
        $w.posted_targets[]?
        | if type == "string" then
            (split("-") | if length >= 2 then {day: (.[0] | norm_day), platform: (.[1] | norm_platform)} else empty end)
          elif type == "object" then
            {day: ((.day // "") | norm_day), platform: ((.platform // "x") | norm_platform)}
          else empty
          end
        | select(.day != "" and .platform != "")
        | "\(.day)-\(.platform)"
      ]
    else
      (($w.posted_days // []) | map(norm_day) | map(select(length > 0)) | unique) as $days
      | (($w.target_platforms // ["x"])
          | if type == "array" and length > 0 then . else ["x"] end
          | map(norm_platform)
          | map(select(length > 0))
          | unique) as $platforms
      | [ $days[] as $d | $platforms[] as $p | "\($d)-\($p)" ]
    end
  | unique
  | sort
' "$STATE_FILE")

OVERLAP_TARGETS=$(jq -nc --argjson req "$REQUEST_TARGETS_JSON" --argjson done "$LAST_POSTED_TARGET_KEYS" '
  [ $req[] as $r | select($done | index($r.key)) | $r ]
')
OVERLAP_TARGET_COUNT=$(jq 'length' <<<"$OVERLAP_TARGETS")
OVERLAP=$(jq -c '[.[].day] | unique | sort' <<<"$OVERLAP_TARGETS")
OVERLAP_COUNT=$(jq 'length' <<<"$OVERLAP")
DUPLICATE_BLOCKED=0

if [ "$OVERLAP_TARGET_COUNT" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  if [ "$PREVIEW" -eq 1 ]; then
    DUPLICATE_BLOCKED=1
  else
    echo "❌ duplicate risk: already sent day-platform targets exist in last_make_webhook"
    echo "overlap_targets: $(jq -r '[.[].key] | join(",")' <<<"$OVERLAP_TARGETS")"
    echo "overlap_days: $(jq -r 'join(",")' <<<"$OVERLAP")"
    echo "use --force to resend explicitly"
    exit 1
  fi
fi

if [ -z "$BATCH_ID" ]; then
  BATCH_ID="manual-$(date -u +%Y%m%dT%H%M%SZ)-Day$(jq -r 'first' <<<"$DAYS_JSON")-Day$(jq -r 'last' <<<"$DAYS_JSON")"
fi

SEND_PAYLOAD=$(jq -nc --arg batch_id "$BATCH_ID" --argjson posts "$POSTS_JSON" '
  {batch_id: $batch_id, posts: $posts}
')

echo "▶ webhook preview"
echo "  - date: $DATE"
echo "  - batch_id: $BATCH_ID"
echo "  - target_days: $(jq -r 'join(",")' <<<"$DAYS_JSON")"
echo "  - target_platforms: $(jq -r 'join(",")' <<<"$PLATFORMS_JSON")"
echo "  - post_count: $POST_COUNT"
echo "  - source_x: $X_SOURCE"
echo "  - source_youtube: $YOUTUBE_SOURCE"
echo "  - x_ready_count: $X_READY_COUNT"
echo "  - youtube_ready_count: $YOUTUBE_READY_COUNT"
echo "  - youtube_pending_asset_count: $YOUTUBE_PENDING_ASSET_COUNT"
echo "  - youtube_blocked_count: $YOUTUBE_BLOCKED_COUNT"
echo "  - youtube_invalid_count: $YOUTUBE_INVALID_COUNT"
echo "  - youtube_missing_video_count: $YOUTUBE_MISSING_VIDEO_COUNT"
echo "  - schedule_policy_file: $( [ -f "$SCHEDULE_POLICY_FILE" ] && echo "${SCHEDULE_POLICY_FILE#$CONTROL_DIR/}" || echo "none" )"
echo "  - schedule_timezone: $SCHEDULE_TIMEZONE"
echo "  - schedule_time_fallback: $SCHEDULE_TIME"
echo "  - schedule_start_offset_days: $SCHEDULE_START_OFFSET_DAYS"
echo "  - overlap_with_last_send_targets: $(jq -r '[.[].key] | join(",")' <<<"$OVERLAP_TARGETS")"
echo "  - overlap_with_last_send_days: $(jq -r 'join(",")' <<<"$OVERLAP")"
echo "  - webhook_url_set: yes"
echo "  - webhook_only: yes"
echo "  - force: $FORCE"
echo "  - duplicate_blocked_without_force: $DUPLICATE_BLOCKED"
echo "  - post_preview:"
jq -r '
    .[]
  | if .platform == "x" then
      "    day=\(.day) platform=\(.platform) dueAt=\(.dueAt // "") text=\((.text // "" | gsub("\n"; " ") | .[0:80]))..."
    else
      "    day=\(.day) platform=\(.platform) dueAt=\(.dueAt // "") title=\((.title // "" | .[0:70]))... videoUrl=\((.videoUrl // "") | .[0:80]) readiness=\((.readiness // "")) missing=\((.missing_fields // []) | join(","))"
    end
' <<<"$POSTS_JSON"

if [ "$(jq 'length' <<<"$YOUTUBE_PREVIEW_JSON")" -gt 0 ]; then
  echo "  - youtube_readiness_preview:"
  jq -r '
    .[]
    | "    day=\(.day) dueAt=\(.dueAt // "") title=\((.title // "" | .[0:60]))... videoUrl_set=\((.videoUrl // "") != "") readiness=\(.readiness // "") missing=\((.missing_fields // []) | join(","))"
  ' <<<"$YOUTUBE_PREVIEW_JSON"
fi

if [ "$PREVIEW" -eq 1 ]; then
  mkdir -p "$REPORT_DIR"
  preview_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  preview_stamp="$(date -u +"%Y-%m-%dT%H-%M-%S")-$RANDOM"
  preview_report_file="$REPORT_DIR/publish_preview_${preview_stamp}.json"
  jq -nc \
    --arg executed_at "$preview_now" \
    --arg date "$DATE" \
    --arg batch_id "$BATCH_ID" \
    --argjson target_days "$DAYS_JSON" \
    --argjson target_platforms "$PLATFORMS_JSON" \
    --argjson request_targets "$REQUEST_TARGETS_JSON" \
    --argjson overlap_targets "$OVERLAP_TARGETS" \
    --argjson overlap_days "$OVERLAP" \
    --argjson x_items "$STATE_X_POSTS_JSON" \
    --argjson youtube_items "$YOUTUBE_PREVIEW_JSON" \
    --argjson posts "$POSTS_JSON" \
    --arg x_source "$X_SOURCE" \
    --arg y_source "$YOUTUBE_SOURCE" \
    --arg timezone "$SCHEDULE_TIMEZONE" \
    --arg policy_file "$( [ -f "$SCHEDULE_POLICY_FILE" ] && echo "${SCHEDULE_POLICY_FILE#$CONTROL_DIR/}" || echo "none" )" \
    '{
      executed_at: $executed_at,
      date: $date,
      batch_id: $batch_id,
      mode: "preview",
      target_days: $target_days,
      target_platforms: $target_platforms,
      duplicate_key_mode: "day-platform",
      requested_targets: $request_targets,
      requested_target_count: ($request_targets | length),
      overlap_targets: $overlap_targets,
      overlap_target_count: ($overlap_targets | length),
      overlap_days: $overlap_days,
      overlap_day_count: ($overlap_days | length),
      source_x: $x_source,
      source_youtube: $y_source,
      schedule_policy_file: $policy_file,
      schedule_timezone: $timezone,
      x_ready_count: ($x_items | length),
      youtube_ready_count: ($youtube_items | map(select(.readiness=="ready")) | length),
      youtube_pending_asset_count: ($youtube_items | map(select(.readiness=="pending_asset")) | length),
      youtube_blocked_count: ($youtube_items | map(select(.readiness=="blocked")) | length),
      youtube_invalid_count: ($youtube_items | map(select(.readiness=="invalid")) | length),
      youtube_missing_video_count: ($youtube_items | map(select((.readiness=="pending_asset") or ((.missing_fields // []) | index("videoUrl")))) | length),
      dueAt_summary: {
        x: ($x_items | map({day, dueAt})),
        youtube: ($youtube_items | map({day, dueAt, readiness}))
      },
      send_targets: ($posts | map({day: (.day|tostring), platform: ((.platform // "x") | ascii_downcase), key: ((.day|tostring) + "-" + ((.platform // "x") | ascii_downcase))}) | unique_by(.key) | sort_by(.day, .platform)),
      webhook_post_count_if_send: ($posts | length),
      youtube_preview: $youtube_items
    }' > "$preview_report_file"
  echo "  - preview_report: ${preview_report_file#$CONTROL_DIR/}"
  if [ "$DUPLICATE_BLOCKED" -eq 1 ]; then
    echo "⚠ preview: overlap detected, actual send requires --force"
  fi
  echo "ℹ preview mode: no send"
  exit 0
fi

response_file=$(mktemp)
http_status=$(curl -sS -o "$response_file" -w "%{http_code}" \
  -X POST "$MAKE_WEBHOOK_URL" \
  -H "x-make-apikey: $MAKE_WEBHOOK_APIKEY" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "$SEND_PAYLOAD" || true)
response_body=$(cat "$response_file")
rm -f "$response_file"

if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
  echo "❌ webhook failed: http=$http_status" >&2
  echo "$response_body" >&2
  exit 1
fi

schedule_preview=$(jq -c '
  if (type == "object") or (type == "array") then
    [
      .. | objects
      | (.scheduled_at? // .scheduled_time? // .schedule_at? // .scheduledAt? // empty)
      | select(type == "string")
    ] | unique | .[:5]
  else
    []
  end
' <<<"$response_body" 2>/dev/null || echo "[]")

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg now "$now" \
   --arg batch_id "$BATCH_ID" \
   --arg response_body "$response_body" \
   --argjson schedule_preview "$schedule_preview" \
   --argjson target_platforms "$PLATFORMS_JSON" \
   --argjson posts "$POSTS_JSON" \
   '
   ($posts | map(.day) | unique) as $posted_days
   | ($posts | map((.platform // "x") | ascii_downcase) | unique) as $target_platforms
   | ($posts | map({day: (.day | tostring), platform: ((.platform // "x") | ascii_downcase), key: ((.day | tostring) + "-" + ((.platform // "x") | ascii_downcase))}) | unique_by(.key) | sort_by(.day, .platform)) as $posted_targets
   | reduce $posts[] as $p (.;
     if .days[$p.day] then .days[$p.day].status = "posted" else . end
   )
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

mkdir -p "$REPORT_DIR"
send_stamp="$(date -u +"%Y-%m-%dT%H-%M-%S")-$RANDOM"
report_file="$REPORT_DIR/make_webhook_send_${send_stamp}.json"
jq -nc \
  --arg executed_at "$now" \
  --arg date "$DATE" \
  --arg batch_id "$BATCH_ID" \
  --arg webhook_path "configured" \
  --arg http_status "$http_status" \
  --arg response_body "$response_body" \
  --argjson target_days "$DAYS_JSON" \
  --argjson target_platforms "$PLATFORMS_JSON" \
  --argjson request_targets "$REQUEST_TARGETS_JSON" \
  --argjson overlap_targets "$OVERLAP_TARGETS" \
  --argjson overlap_days "$OVERLAP" \
  --argjson x_items "$STATE_X_POSTS_JSON" \
  --argjson youtube_items "$YOUTUBE_PREVIEW_JSON" \
  --argjson posts "$POSTS_JSON" \
  --argjson schedule_preview "$schedule_preview" \
  '{
    executed_at: $executed_at,
    date: $date,
    batch_id: $batch_id,
    webhook_path: $webhook_path,
    http_status: ($http_status | tonumber),
    target_days: $target_days,
    target_platforms: $target_platforms,
    duplicate_key_mode: "day-platform",
    requested_targets: $request_targets,
    requested_target_count: ($request_targets | length),
    overlap_targets: $overlap_targets,
    overlap_target_count: ($overlap_targets | length),
    overlap_days: $overlap_days,
    overlap_day_count: ($overlap_days | length),
    x_ready_count: ($x_items | length),
    youtube_ready_count: ($youtube_items | map(select(.readiness=="ready")) | length),
    youtube_pending_asset_count: ($youtube_items | map(select(.readiness=="pending_asset")) | length),
    youtube_blocked_count: ($youtube_items | map(select(.readiness=="blocked")) | length),
    youtube_invalid_count: ($youtube_items | map(select(.readiness=="invalid")) | length),
    youtube_missing_video_count: ($youtube_items | map(select((.readiness=="pending_asset") or ((.missing_fields // []) | index("videoUrl")))) | length),
    sent_posts: ($posts | map(if .platform == "x" then {
      day,
      platform,
      dueAt,
      text_preview: ((.text // "")|gsub("\n";" ")|.[0:120])
    } else {
      day,
      platform,
      dueAt,
      readiness: (.readiness // ""),
      title_preview: ((.title // "")|.[0:120]),
      videoUrl: (.videoUrl // "")
    } end)),
    dueAt_summary: {
      x: ($x_items | map({day, dueAt})),
      youtube: ($youtube_items | map({day, dueAt, readiness}))
    },
    sent_target_count: ($posts | map({day: (.day|tostring), platform: ((.platform // "x") | ascii_downcase), key: ((.day|tostring) + "-" + ((.platform // "x") | ascii_downcase))}) | unique_by(.key) | length),
    sent_targets: ($posts | map({day: (.day|tostring), platform: ((.platform // "x") | ascii_downcase), key: ((.day|tostring) + "-" + ((.platform // "x") | ascii_downcase))}) | unique_by(.key) | sort_by(.day, .platform)),
    sent_post_count: ($posts | length),
    skipped_summary: {
      duplicate_overlap_target_count: ($overlap_targets | length),
      youtube_pending_asset_count: ($youtube_items | map(select(.readiness=="pending_asset")) | length),
      youtube_blocked_count: ($youtube_items | map(select(.readiness=="blocked")) | length),
      youtube_invalid_count: ($youtube_items | map(select(.readiness=="invalid")) | length)
    },
    schedule_preview: $schedule_preview,
    response_body: ($response_body | .[0:2000])
  }' > "$report_file"

echo "✅ webhook sent"
echo "  - batch_id: $BATCH_ID"
echo "  - posted_days: $(jq -r '[.[].day] | unique | join(",")' <<<"$POSTS_JSON")"
echo "  - posted_targets: $(jq -r '[.[] | ((.day|tostring) + "-" + ((.platform // "x") | ascii_downcase))] | unique | join(",")' <<<"$POSTS_JSON")"
echo "  - report: ${report_file#$CONTROL_DIR/}"
