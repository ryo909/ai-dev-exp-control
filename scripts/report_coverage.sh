#!/usr/bin/env bash
set -euo pipefail
CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$CONTROL_DIR/STATE.json"
OUT_DIR="$CONTROL_DIR/reports"
mkdir -p "$OUT_DIR"

if [ ! -f "$STATE" ]; then
  echo "⚠ report_coverage: STATE.json not found, skip"
  exit 0
fi

jq -c '
def count_by(path):
  [ .days | to_entries[] | .value.meta | getpath(path) ]
  | map(select(. != null))
  | group_by(.)
  | map({key: .[0], count: length})
  | sort_by(.count) | reverse;

def dup_by(path):
  [ .days | to_entries[] | {day: .key, v: (.value.meta | getpath(path))} ]
  | map(select(.v != null))
  | group_by(.v)
  | map(select(length > 1))
  | sort_by(length) | reverse;

{
  generated_at: (now|todateiso8601),
  genres: count_by(["genre"]),
  core_actions: count_by(["core_action"]),
  themes: count_by(["theme"]),
  dup_one_sentence: dup_by(["one_sentence"]),
  dup_core_twist: (
    [ .days | to_entries[] | {day: .key, k: ((.value.meta.core_action // "") + " | " + (.value.meta.twist // ""))} ]
    | map(select(.k != " | "))
    | group_by(.k)
    | map(select(length > 1))
    | sort_by(length) | reverse
  )
}
' "$STATE" > "$OUT_DIR/coverage.json"

{
  echo "# Coverage report"
  echo ""
  echo "generated_at: $(jq -r '.generated_at' "$OUT_DIR/coverage.json")"
  echo ""

  echo "## genres"
  echo "| key | count |"
  echo "|---|---:|"
  jq -r '.genres[]? | "| \(.key) | \(.count) |"' "$OUT_DIR/coverage.json"
  echo ""

  echo "## core_actions"
  echo "| key | count |"
  echo "|---|---:|"
  jq -r '.core_actions[]? | "| \(.key) | \(.count) |"' "$OUT_DIR/coverage.json"
  echo ""

  echo "## themes"
  echo "| key | count |"
  echo "|---|---:|"
  jq -r '.themes[]? | "| \(.key) | \(.count) |"' "$OUT_DIR/coverage.json"
  echo ""

  echo "## duplicates: core_action | twist (top 10)"
  jq -r '.dup_core_twist[:10][]? | "- **\(.[0].k)**: " + (map("Day"+.day) | join(", "))' "$OUT_DIR/coverage.json" 2>/dev/null || true
  echo ""

  echo "## duplicates: one_sentence (top 10)"
  jq -r '.dup_one_sentence[:10][]? | "- **\(.[0].v)**: " + (map("Day"+.day) | join(", "))' "$OUT_DIR/coverage.json" 2>/dev/null || true
  echo ""
} > "$OUT_DIR/coverage.md"

echo "✅ report_coverage: wrote reports/coverage.*"
