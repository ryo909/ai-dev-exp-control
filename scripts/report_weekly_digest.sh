#!/usr/bin/env bash
set -euo pipefail

CONTROL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$CONTROL_DIR/reports"
SIGNALS_MD="$CONTROL_DIR/shared-context/SIGNALS.md"
COVERAGE_JSON="$CONTROL_DIR/reports/coverage.json"
MEMORY_MD="$CONTROL_DIR/memory/MEMORY.md"
FEEDBACK_MD="$CONTROL_DIR/shared-context/FEEDBACK-LOG.md"
LOG_DIR="$CONTROL_DIR/logs"
STATE_JSON="$CONTROL_DIR/STATE.json"

mkdir -p "$REPORTS_DIR"

now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
today="$(date -u +"%Y-%m-%d")"

branch="$(git -C "$CONTROL_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
head_sha="$(git -C "$CONTROL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

last_run=""
if [ -f "$STATE_JSON" ] && command -v jq >/dev/null 2>&1; then
  last_run="$(jq -r '.last_run // empty' "$STATE_JSON" 2>/dev/null || true)"
fi

out="$REPORTS_DIR/weekly_digest.md"

{
  echo "# Weekly Digest (${today})"
  echo ""
  echo "- generated_at: ${now}"
  echo "- branch: ${branch}"
  echo "- head: ${head_sha}"
  if [ -n "$last_run" ]; then
    echo "- STATE.last_run: ${last_run}"
  fi
  echo ""

  echo "## Signals (top)"
  if [ -f "$SIGNALS_MD" ]; then
    grep -E '^\- ' "$SIGNALS_MD" | head -n 20 || true
    echo ""
    echo "_source: shared-context/SIGNALS.md_"
  else
    echo "_SIGNALS.md not found (run research_refresh first)._"
  fi
  echo ""

  echo "## Coverage highlights"
  if [ -f "$COVERAGE_JSON" ] && command -v jq >/dev/null 2>&1; then
    echo "### top genres"
    jq -r '.genres[:5][]? | "- " + .key + " (" + (.count|tostring) + ")"' "$COVERAGE_JSON" 2>/dev/null || true
    echo ""
    echo "### top core_actions"
    jq -r '.core_actions[:5][]? | "- " + .key + " (" + (.count|tostring) + ")"' "$COVERAGE_JSON" 2>/dev/null || true
    echo ""
    echo "### duplicates (core_action | twist) top 5"
    jq -r '.dup_core_twist[:5][]? | "- " + (.[0].k) + " : " + (map("Day"+.day) | join(", "))' "$COVERAGE_JSON" 2>/dev/null || true
    echo ""
    echo "### duplicates (one_sentence) top 5"
    jq -r '.dup_one_sentence[:5][]? | "- " + (.[0].v) + " : " + (map("Day"+.day) | join(", "))' "$COVERAGE_JSON" 2>/dev/null || true
    echo ""
    echo "_source: reports/coverage.json_"
  else
    echo "_coverage.json not found yet (it will appear after running a batch)._"
  fi
  echo ""

  echo "## Learnings (this week material)"
  echo "### MEMORY.md (tail)"
  if [ -f "$MEMORY_MD" ]; then
    (grep -E '^\- ' "$MEMORY_MD" | tail -n 15) 2>/dev/null || true
    echo ""
    echo "_source: memory/MEMORY.md_"
  else
    echo "_MEMORY.md not found._"
  fi
  echo ""

  echo "### FEEDBACK-LOG.md (tail)"
  if [ -f "$FEEDBACK_MD" ]; then
    (grep -E '^\- ' "$FEEDBACK_MD" | tail -n 15) 2>/dev/null || true
    echo ""
    echo "_source: shared-context/FEEDBACK-LOG.md_"
  else
    echo "_FEEDBACK-LOG.md not found._"
  fi
  echo ""

  echo "### Recent failures (logs summaries)"
  if [ -d "$LOG_DIR" ]; then
    summaries="$(ls -t "$LOG_DIR"/Day*.summary.md 2>/dev/null | head -n 5 || true)"
    if [ -n "${summaries}" ]; then
      while read -r f; do
        [ -z "$f" ] && continue
        echo "- $(basename "$f")"
        sed -n '1,10p' "$f" | sed 's/^/  /' || true
      done <<< "$summaries"
    else
      echo "_no Day*.summary.md found_"
    fi
  else
    echo "_logs/ not found_"
  fi
  echo ""

  echo "## Next actions"
  echo "- Update shared-context/THESIS.md (see 更新手順セクション)"
  echo "- If needed, add notes to shared-context/FEEDBACK-LOG.md and memory/MEMORY.md"
  echo "- Revise system/prompts/weekly_run.md for next week using this digest"
} > "$out"

echo "✅ weekly_digest: wrote $out"
