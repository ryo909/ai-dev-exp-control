#!/usr/bin/env bash
# ============================================================
# smoke_test.sh — foundation追記の軽量チェック
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
STATE_PATH=""
CATALOG_PATH=""

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
  return 1
}

resolve_any_file() {
  local candidate
  for candidate in "$@"; do
    if [ -f "$CONTROL_DIR/$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

echo "[smoke_test] start"

if command -v python3 >/dev/null 2>&1; then
  echo "[PASS] tool: python3"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] tool: python3 not found"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

if command -v rg >/dev/null 2>&1; then
  echo "[PASS] tool: rg"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] tool: rg not found"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo "== smoke_test: foundation files =="
check_file "system/contract.md"
check_file "improvements/backlog.md"
check_file "improvements/next_pick.md"
check_file "rubrics/system_rubric.md"
check_file "rules/checklist.md"
check_file "agents/registry.md"
check_file "telemetry/run_log.jsonl"
check_file "templates/posts/header.txt"
check_file "templates/posts/footer.txt"
check_file "templates/posts/body_A.txt"
check_file "templates/posts/body_B.txt"
check_file "templates/posts/body_C.txt"
check_file "templates/posts/body_D.txt"
check_file "experiments/EXP-000_template.md"
check_file "experiments/exp_index.md"
check_file "scripts/contract_check.sh"


echo "== smoke_test: existing core files =="
STATE_PATH=$(resolve_any_file "state.json" "STATE.json" || true)
CATALOG_PATH=$(resolve_any_file "catalog.json" "catalog/catalog.json" || true)
check_any_file "state.json" "state.json" "STATE.json"
check_any_file "catalog.json" "catalog.json" "catalog/catalog.json"
check_file "scripts/resume.sh"


echo "== smoke_test: json parse check =="
if [ -n "$STATE_PATH" ] && [ -n "$CATALOG_PATH" ] && command -v python3 >/dev/null 2>&1; then
  if python3 - <<PY
import json
from pathlib import Path
for p in [Path("$CONTROL_DIR") / "$STATE_PATH", Path("$CONTROL_DIR") / "$CATALOG_PATH"]:
    with p.open("r", encoding="utf-8") as f:
        json.load(f)
print("[smoke_test] JSON parse OK")
PY
  then
    echo "[PASS] json parse"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] json parse"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "[FAIL] json parse prerequisites missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi


echo "== smoke_test: post template rendering =="
if command -v python3 >/dev/null 2>&1; then
  if (cd "$CONTROL_DIR" && python3 - <<'PY'
from pathlib import Path

def read(p):
    return Path(p).read_text(encoding="utf-8").strip("\n")

header = read("templates/posts/header.txt")
footer = read("templates/posts/footer.txt")
body = read("templates/posts/body_A.txt")

vals = {
    "DAY": "008",
    "TOOL_NAME": "Dummy Tool",
    "PAGES_URL": "https://example.com",
    "ONE_LINER": "ダミーの1行説明",
    "USE_CASE": "ダミーの用途",
}


def render(s: str) -> str:
    for k, v in vals.items():
        s = s.replace("{{" + k + "}}", v)
    return s

out = "\n".join([render(header), render(body), render(footer)])
assert "Day008" in out
assert "https://example.com" in out
print("[smoke_test] render OK")
PY
  )
  then
    echo "[PASS] template render"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] template render"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "[FAIL] template render prerequisites missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi


echo "== smoke_test: contract check =="
if (cd "$CONTROL_DIR" && bash scripts/contract_check.sh); then
  echo "[PASS] contract_check"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "[FAIL] contract_check"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo "== smoke_test summary =="
echo "PASS: $PASS_COUNT"
echo "FAIL: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

echo "[smoke_test] OK"
