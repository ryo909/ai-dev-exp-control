#!/usr/bin/env bash
# ============================================================
# smoke_test.sh — foundation追記の軽量チェック
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

check_file() {
  local file_path="$1"
  if [ -f "$CONTROL_DIR/$file_path" ]; then
    echo "[PASS] $file_path"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] $file_path"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check_any_file() {
  local label="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [ -f "$CONTROL_DIR/$candidate" ]; then
      echo "[PASS] $label -> $candidate"
      PASS_COUNT=$((PASS_COUNT + 1))
      return 0
    fi
  done
  echo "[FAIL] $label"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "== smoke_test: foundation files =="
check_file "system/contract.md"
check_file "templates/posts/header.txt"
check_file "templates/posts/footer.txt"
check_file "templates/posts/body_A.txt"
check_file "templates/posts/body_B.txt"
check_file "templates/posts/body_C.txt"
check_file "templates/posts/body_D.txt"
check_file "improvements/backlog.md"
check_file "rubrics/system_rubric.md"
check_file "agents/registry.md"
check_file "telemetry/run_log.jsonl"


echo "== smoke_test: existing core files =="
check_any_file "state.json" "state.json" "STATE.json"
check_any_file "catalog.json" "catalog.json" "catalog/catalog.json"
check_file "scripts/resume.sh"


echo "== smoke_test: post template rendering =="
if [ -f "$CONTROL_DIR/scripts/render_post_text.py" ] && command -v python3 >/dev/null 2>&1; then
  if python3 "$CONTROL_DIR/scripts/render_post_text.py" \
    --day "001" \
    --tool-name "Smoke Tool" \
    --pages-url "https://example.com/day001/" \
    --body-id "A" \
    --one-liner "これはスモークテストです。" \
    --use-case "用途: 導入確認" >/dev/null; then
    echo "[PASS] render_post_text.py"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] render_post_text.py"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "[SKIP] render_post_text.py check (python3 or script missing)"
fi

echo "== smoke_test summary =="
echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
