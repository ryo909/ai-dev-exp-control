#!/usr/bin/env bash
set -euo pipefail
CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES_MD="$CONTROL_DIR/shared-context/SOURCES.md"
SHORTLIST="$CONTROL_DIR/idea_bank/shortlist.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠ update_sources_stats: jq not found, skip"
  exit 0
fi

if [ ! -f "$SOURCES_MD" ] || [ ! -f "$SHORTLIST" ]; then
  echo "⚠ update_sources_stats: missing SOURCES.md or shortlist.json, skip"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠ update_sources_stats: python3 not found, skip"
  exit 0
fi

tmp="$(mktemp)"
stats="$(jq -r '
  (.items // [])
  | map(select(((.tags//[])|index("collector_error"))|not))
  | group_by(.source)
  | map({source: .[0].source, count: length})
  | sort_by(.count) | reverse
' "$SHORTLIST" 2>/dev/null || echo "[]")"

{
  echo "<!-- AUTO_STATS_START -->"
  echo "## AUTO統計（shortlist内の件数）"
  echo "- generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
  echo "| source | count |"
  echo "|---|---:|"
  echo "$stats" | jq -r '.[]? | "| " + .source + " | " + (.count|tostring) + " |"'
  echo "<!-- AUTO_STATS_END -->"
} > "$tmp"

# 置換（AUTO領域を書き換え）
python3 - <<'PY' "$SOURCES_MD" "$tmp"
import sys, re, pathlib
md = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
rep = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
new = re.sub(r'<!-- AUTO_STATS_START -->.*<!-- AUTO_STATS_END -->', rep, md, flags=re.S)
pathlib.Path(sys.argv[1]).write_text(new, encoding="utf-8")
PY

rm -f "$tmp"
echo "✅ update_sources_stats: updated SOURCES.md"
