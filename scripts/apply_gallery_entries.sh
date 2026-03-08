#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG_DIR="$CONTROL_DIR/catalog"
STATE_FILE="$CONTROL_DIR/STATE.json"

DATE=""
DAYS_CSV=""
PREVIEW=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/apply_gallery_entries.sh --date YYYY-MM-DD --days 009,010,... [--preview]

Options:
  --date      gallery_entries_<date>.json を指定
  --days      反映対象 day (3桁CSV)
  --preview   ファイルは更新せず差分要約のみ表示
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

if [ -z "$DATE" ] || [ -z "$DAYS_CSV" ]; then
  usage
  exit 1
fi

SOURCE_FILE="$CONTROL_DIR/exports/launch/gallery_entries_${DATE}.json"
CATALOG_JSON="$CATALOG_DIR/catalog.json"
LATEST_JSON="$CATALOG_DIR/latest.json"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "❌ source missing: ${SOURCE_FILE#$CONTROL_DIR/}" >&2
  exit 1
fi
if [ ! -f "$CATALOG_JSON" ] || [ ! -f "$LATEST_JSON" ]; then
  echo "❌ catalog files missing under catalog/" >&2
  exit 1
fi

DAYS_JSON=$(jq -nc --arg csv "$DAYS_CSV" '
  ($csv
   | split(",")
   | map(gsub("[^0-9]"; ""))
   | map(select(length > 0))
   | map((. | tonumber) as $n | ($n|tostring) | if length==1 then "00"+. elif length==2 then "0"+. else . end)
  ) | unique
')

if [ "$(jq 'length' <<<"$DAYS_JSON")" -eq 0 ]; then
  echo "❌ days parse failed: $DAYS_CSV" >&2
  exit 1
fi

SELECTED_ENTRIES=$(jq -c \
  --argjson days "$DAYS_JSON" \
  --argjson state "$(cat "$STATE_FILE")" '
  [
    .[]
    | (.day | tostring | ltrimstr("Day")) as $d
    | select($days | index($d))
    | {
        day: $d,
        tool_name: (.title // ""),
        one_sentence: (.one_line // ""),
        pages_url: (.pages_url // ""),
        repo_url: (.repo_url // ""),
        status: ($state.days[$d].status // "done")
      }
  ] | sort_by(.day)
' "$SOURCE_FILE")

SELECTED_COUNT=$(jq 'length' <<<"$SELECTED_ENTRIES")
if [ "$SELECTED_COUNT" -eq 0 ]; then
  echo "❌ selected entries empty for days=$DAYS_CSV" >&2
  exit 1
fi

SUMMARY=$(jq -nc \
  --argjson existing "$(cat "$CATALOG_JSON")" \
  --argjson selected "$SELECTED_ENTRIES" '
  {
    selected_days: ($selected | map(.day)),
    selected_count: ($selected | length),
    update_count: ([ $selected[] as $s | select($existing | map(.day) | index($s.day)) ] | length),
    add_count: ([ $selected[] as $s | select((($existing | map(.day) | index($s.day)) | not)) ] | length)
  }
')

echo "▶ gallery apply target: catalog/catalog.json + catalog/latest.json"
jq '.' <<<"$SUMMARY"

if [ "$PREVIEW" -eq 1 ]; then
  echo "ℹ preview mode: no files updated"
  exit 0
fi

tmp_catalog=$(mktemp)
tmp_latest=$(mktemp)

jq -nc \
  --argjson existing "$(cat "$CATALOG_JSON")" \
  --argjson selected "$SELECTED_ENTRIES" '
  ($existing + $selected)
  | group_by(.day)
  | map(reduce .[] as $x ({}; . * $x))
  | sort_by(.day)
' > "$tmp_catalog"

jq -nc \
  --argjson existing "$(cat "$LATEST_JSON")" \
  --argjson selected "$SELECTED_ENTRIES" '
  ($existing + $selected)
  | group_by(.day)
  | map(reduce .[] as $x ({}; . * $x))
  | sort_by(.day)
  | .[-7:]
' > "$tmp_latest"

mv "$tmp_catalog" "$CATALOG_JSON"
mv "$tmp_latest" "$LATEST_JSON"

echo "✅ applied gallery entries to:"
echo "  - ${CATALOG_JSON#$CONTROL_DIR/}"
echo "  - ${LATEST_JSON#$CONTROL_DIR/}"
