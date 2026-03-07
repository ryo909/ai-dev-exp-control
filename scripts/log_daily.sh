#!/usr/bin/env bash
set -euo pipefail

CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAY_NUM="${1:-}"
STATUS="${2:-}"
DETAIL="${3:-}"

if [ -z "$DAY_NUM" ] || [ -z "$STATUS" ]; then
  echo "usage: log_daily.sh <day_num> <success|fail> [detail]"
  exit 0
fi

mkdir -p "$CONTROL_DIR/memory/daily"
today="$(date -u +"%Y-%m-%d")"
now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
file="$CONTROL_DIR/memory/daily/${today}.md"

# STATEからmetaを引く（無ければ空）
genre=""
theme=""
core=""
twist=""
one=""
repo=""
if command -v jq >/dev/null 2>&1 && [ -f "$CONTROL_DIR/STATE.json" ]; then
  node=".days[\"${DAY_NUM}\"]"
  genre="$(jq -r "${node}.meta.genre // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
  theme="$(jq -r "${node}.meta.theme // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
  core="$(jq -r "${node}.meta.core_action // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
  twist="$(jq -r "${node}.meta.twist // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
  one="$(jq -r "${node}.meta.one_sentence // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
  repo="$(jq -r "${node}.repo_url // empty" "$CONTROL_DIR/STATE.json" 2>/dev/null || true)"
fi

{
  echo ""
  echo "## ${now} — Day${DAY_NUM} (${STATUS})"
  echo "- genre: ${genre}"
  echo "- theme: ${theme}"
  echo "- core_action: ${core}"
  echo "- twist: ${twist}"
  echo "- one_sentence: ${one}"
  if [ -n "$repo" ]; then echo "- repo: ${repo}"; fi
  if [ -n "$DETAIL" ]; then echo "- detail: ${DETAIL}"; fi
} >> "$file"

echo "✅ daily log appended: $file"
