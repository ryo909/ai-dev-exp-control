#!/usr/bin/env bash
set -euo pipefail

echo "[contract_check] start"

if ! command -v rg >/dev/null 2>&1; then
  echo "[contract_check] FAIL: ripgrep (rg) not found"
  exit 1
fi

# 1) 投稿テンプレ規約：bodyにURL/タグを入れない（footer固定）
for f in templates/posts/body_*.txt; do
  if [ -f "$f" ]; then
    if rg -n "https?://|#個人開発|#100日開発" "$f" >/dev/null 2>&1; then
      echo "[contract_check] FAIL: URL or hashtags found in $f (should be in footer only)"
      exit 1
    fi
  fi
done

# 2) header/footerの最低要件
if [ ! -f templates/posts/header.txt ] || [ ! -f templates/posts/footer.txt ]; then
  echo "[contract_check] FAIL: templates/posts/header.txt or footer.txt missing"
  exit 1
fi

# footer には URL placeholder と hashtags があるべき（厳密すぎない程度に確認）
if ! rg -n "\{\{PAGES_URL\}\}" templates/posts/footer.txt >/dev/null 2>&1; then
  echo "[contract_check] FAIL: footer missing {{PAGES_URL}} placeholder"
  exit 1
fi
if ! rg -n "#個人開発" templates/posts/footer.txt >/dev/null 2>&1; then
  echo "[contract_check] FAIL: footer missing #個人開発"
  exit 1
fi
if ! rg -n "#100日開発" templates/posts/footer.txt >/dev/null 2>&1; then
  echo "[contract_check] FAIL: footer missing #100日開発"
  exit 1
fi

# 3) 秘匿露出の簡易検査（危険語スキャン）
# ※誤検知しうるため、強すぎないパターンにする
# 露骨な token= / api_key / webhook url の直書きを検出したらNG
if rg -n --hidden --glob '!.git/**' --glob '!.env*' --glob '!scripts/contract_check.sh' "(?i)(\\btoken\\b\\s*=|\\bapi[_-]?key\\b\\s*=|\\bsecret\\b\\s*=|\\bwebhook\\b\\s*=|hooks\\.zapier\\.com|maker\\.ifttt\\.com)" . >/dev/null 2>&1; then
  echo "[contract_check] FAIL: potential secret/webhook/token exposure found"
  echo "Hint: search the matches and mask/remove before commit."
  exit 1
fi

echo "[contract_check] OK"
