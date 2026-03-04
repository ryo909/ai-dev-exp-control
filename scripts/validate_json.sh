#!/usr/bin/env bash
set -euo pipefail
SCHEMA=${1:?"schema path required"}
DATA=${2:?"data path required"}

if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then
  echo "⚠ validate_json: node/npx not found, skip"
  exit 0
fi

tmp=$(mktemp)
set +e
npx -y ajv-cli@5 validate -s "$SCHEMA" -d "$DATA" --errors=text >"$tmp" 2>&1
code=$?
set -e

# npx download / network failures → skip
if grep -Eqi "npm ERR|ENOTFOUND|EAI_AGAIN|ECONN|network|timed out|Could not resolve|fetch failed" "$tmp"; then
  echo "⚠ validate_json: npx download/network error, skip"
  tail -n 30 "$tmp" || true
  rm -f "$tmp"
  exit 0
fi

if [ $code -ne 0 ]; then
  echo "❌ validate_json: schema invalid for $DATA"
  cat "$tmp"
  rm -f "$tmp"
  exit 1
fi

echo "✅ validate_json: ok ($DATA)"
rm -f "$tmp"
