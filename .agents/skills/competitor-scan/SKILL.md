---
name: competitor-scan
description: "shortlist上位のURLをブラウザで開いて構成/フック/CTAを抽出し、今日のtwistを『競合との差分が一文で言える』形に強化する必要があるときに使う。コード変更ではなく、調査→要約→提案→ファイル出力が目的。"
---

# Purpose
- `idea_bank/shortlist.json` の上位候補（デフォルト3件、最大5件）を対象に、
  - 見出し構造（H1-H3）
  - 冒頭フック（最初の段落の要点）
  - CTA（末尾の誘導/リンク/行動要求）
  - 口調テンプレ（頻出フレーズ）
  を抽出する。
- その結果から「競合との差分が一文で言える」twist案を3つ、one_sentence案を2つ作り、提案として出す。

# Inputs
- `idea_bank/shortlist.json`
- （任意）対象Day番号（例：Day042）。指定があれば、その日のmeta（STATE.json）を読み、twist/one_sentence改善案を出す。

# Tools
- ブラウザ操作は Playwright MCP を優先する。
- URLが開けない/不安定な場合は、フォールバックとして title/OG/見出しだけで要点推定し「推定」と明記する。

# Output (files)
- `reports/competitors/competitor_scan_<YYYY-MM-DD>.md` を生成（追記ではなく新規）。
  構成：
  1) 対象URL一覧
  2) 各記事の抽出結果（見出し/フック/CTA）
  3) 共通パターン
  4) 差分化の提案（twist案3つ、one_sentence案2つ）
  5) “やらないこと”（真似しないポイント）を1つ

# Guardrails
- 引用は短く（要点は自分の言葉で要約）。長文転載は禁止。
- 作業は read-only（このスキル自体はコード変更しない）。
- 出力は必ずファイルに残す（後で週次digestに利用する）。

# How to run
- UIで `/skills` → List skills から competitor-scan を選ぶか、プロンプト内で `$competitor-scan` と書いて起動する。
- 例：
  "$competitor-scan: shortlist上位3件を調査して、Day042のtwist/one_sentence改善案を出し、reports/competitors に保存して"
