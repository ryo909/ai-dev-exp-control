#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$CONTROL_DIR/STATE.json"
ENV_FILE="$CONTROL_DIR/.env.local"
REPORT_DIR="$CONTROL_DIR/reports/publish"

DATE=""
DAYS_CSV=""
PREVIEW=0
FORCE=0
WEBHOOK_ONLY=0
BATCH_ID=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only [--preview] [--force] [--batch-id ID]

Rules:
  - --webhook-only は必須
  - 既に last_make_webhook.posted_days に含まれる day を送る場合は --force 必須
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

DAYS_JSON=$(jq -nc --arg csv "$DAYS_CSV" '
  ($csv
   | split(",")
   | map(gsub("[^0-9]"; ""))
   | map(select(length > 0))
   | map((. | tonumber) as $n | ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end)
  ) | unique | sort
')

REQ_COUNT=$(jq 'length' <<<"$DAYS_JSON")
if [ "$REQ_COUNT" -eq 0 ]; then
  echo "❌ days parse failed: $DAYS_CSV" >&2
  exit 1
fi

POSTS_JSON=$(jq -c --argjson days "$DAYS_JSON" '
  [ $days[] as $d
    | .days[$d] as $entry
    | select($entry)
    | {
        day: $d,
        text: ($entry.post_texts.standard // $entry.post_texts.compact // $entry.post_texts.minimal // ""),
        status: ($entry.status // "")
      }
    | select(.text != "")
  ] | sort_by(.day) | reverse
' "$STATE_FILE")

POST_COUNT=$(jq 'length' <<<"$POSTS_JSON")
if [ "$POST_COUNT" -ne "$REQ_COUNT" ]; then
  echo "❌ some days missing post text (requested=$REQ_COUNT, ready=$POST_COUNT)" >&2
  echo "requested: $(jq -r 'join(",")' <<<"$DAYS_JSON")" >&2
  echo "ready: $(jq -r '[.[].day] | join(",")' <<<"$POSTS_JSON")" >&2
  exit 1
fi

LAST_POSTED=$(jq -c '.last_make_webhook.posted_days // []' "$STATE_FILE")
OVERLAP=$(jq -nc --argjson req "$DAYS_JSON" --argjson done "$LAST_POSTED" '$req | map(select($done | index(.)))')
OVERLAP_COUNT=$(jq 'length' <<<"$OVERLAP")
DUPLICATE_BLOCKED=0

if [ "$OVERLAP_COUNT" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  if [ "$PREVIEW" -eq 1 ]; then
    DUPLICATE_BLOCKED=1
  else
    echo "❌ duplicate risk: already sent days exist in last_make_webhook"
    echo "overlap: $(jq -r 'join(",")' <<<"$OVERLAP")"
    echo "use --force to resend explicitly"
    exit 1
  fi
fi

if [ -z "$BATCH_ID" ]; then
  BATCH_ID="manual-$(date -u +%Y%m%dT%H%M%SZ)-Day$(jq -r 'first' <<<"$DAYS_JSON")-Day$(jq -r 'last' <<<"$DAYS_JSON")"
fi

SEND_PAYLOAD=$(jq -nc --arg batch_id "$BATCH_ID" --argjson posts "$(jq -c '[ .[] | {day,text} ]' <<<"$POSTS_JSON")" '
  {batch_id: $batch_id, posts: $posts}
')

echo "▶ webhook preview"
echo "  - date: $DATE"
echo "  - batch_id: $BATCH_ID"
echo "  - target_days: $(jq -r 'join(",")' <<<"$DAYS_JSON")"
echo "  - post_count: $POST_COUNT"
echo "  - overlap_with_last_send: $(jq -r 'join(",")' <<<"$OVERLAP")"
echo "  - webhook_url_set: yes"
echo "  - webhook_only: yes"
echo "  - force: $FORCE"
echo "  - duplicate_blocked_without_force: $DUPLICATE_BLOCKED"
echo "  - first_post_preview:"
jq -r '.[0] | "    day=\(.day) text=\(.text | gsub("\n"; " ") | .[0:80])..."' <<<"$POSTS_JSON"

if [ "$PREVIEW" -eq 1 ]; then
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
   --argjson posts "$(jq -c '[ .[] | {day,text} ]' <<<"$POSTS_JSON")" \
   '
   reduce $posts[] as $p (.;
     if .days[$p.day] then .days[$p.day].status = "posted" else . end
   )
   | .last_make_webhook = {
       batch_id: $batch_id,
       sent_at: $now,
       posted_count: ($posts | length),
       posted_days: ($posts | map(.day)),
       schedule_preview: $schedule_preview,
       response_body: ($response_body | .[0:400])
     }
   | .last_run_at = $now
   | .execution_logs = ((.execution_logs // []) + [{
       executed_at: $now,
       phase: "buffer",
       batch_id: $batch_id,
       posted_count: ($posts | length),
       posted_days: ($posts | map(.day)),
       schedule_preview: $schedule_preview
     }])
   ' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

mkdir -p "$REPORT_DIR"
report_file="$REPORT_DIR/make_webhook_send_${now//[:]/-}.json"
jq -nc \
  --arg executed_at "$now" \
  --arg date "$DATE" \
  --arg batch_id "$BATCH_ID" \
  --arg webhook_path "configured" \
  --arg http_status "$http_status" \
  --arg response_body "$response_body" \
  --argjson target_days "$DAYS_JSON" \
  --argjson posts "$POSTS_JSON" \
  --argjson schedule_preview "$schedule_preview" \
  '{
    executed_at: $executed_at,
    date: $date,
    batch_id: $batch_id,
    webhook_path: $webhook_path,
    http_status: ($http_status | tonumber),
    target_days: $target_days,
    sent_posts: ($posts | map({day,text_preview:(.text|gsub("\n";" ")|.[0:120])})),
    schedule_preview: $schedule_preview,
    response_body: ($response_body | .[0:2000])
  }' > "$report_file"

echo "✅ webhook sent"
echo "  - batch_id: $BATCH_ID"
echo "  - posted_days: $(jq -r '[.[].day] | join(",")' <<<"$POSTS_JSON")"
echo "  - report: ${report_file#$CONTROL_DIR/}"
