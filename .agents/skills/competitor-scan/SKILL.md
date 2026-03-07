---
name: competitor-scan
description: "shortlist上位のURLをブラウザで開いて構成/フック/CTAを抽出し、今日のtwistを『競合との差分が一文で言える』形に強化する必要があるときに使う。コード変更ではなく、調査→要約→提案→ファイル出力が目的。"
---

# Purpose
- `idea_bank/shortlist.json` の上位候補を対象に、
  - 見出し構造（H1-H3）
  - 冒頭フック（最初の段落の要点）
  - CTA（末尾の誘導/リンク/行動要求）
  - 口調テンプレ（頻出フレーズ）
  を抽出する。
- その結果から「競合との差分が一文で言える」twist案を3つ、one_sentence案を2つ作り、提案として出す。
- 取得不能URLは `blocked` / `failed` として記録し、`ok` のみで分析・提案を作る。

# Inputs
- `idea_bank/shortlist.json`
- （任意）対象Day番号（例：Day042）。指定があれば、その日のmeta（STATE.json）を読み、twist/one_sentence改善案を出す。
- 既定パラメータ:
  - `success_target = 3`（最大5まで）
  - `max_candidates = 10`（shortlist先頭から最大10件）

# Tools
- ブラウザ操作は Playwright MCP を優先する。
- URLが開けない/不安定な場合は `failed` として記録する。
- 以下の判定に一致した場合は `blocked` として扱い、本文抽出は行わずスキップする:
  - `Just a moment`
  - `Checking your browser`
  - `Performing security verification`
  - `Verification successful`
  - `Cloudflare`
  - `Access denied`
- 判定対象は title / 本文先頭 / 主要見出し（H1-H3）とし、明らかな bot/verification 応答ドメインも `blocked` とする。
- `blocked` / `failed` はレポートに残すが、共通パターン・twist・one_sentenceの根拠から除外する。
- `ok` が `success_target` に達するまで次候補へ繰り上げる。`max_candidates` に達して不足した場合は不足数を明記する。

# Output (files)
- 以下の2ファイルを生成:
  - `reports/competitors/competitor_scan_<YYYY-MM-DD>_shortlist.md`
  - `reports/competitors/competitor_scan_<YYYY-MM-DD>_shortlist.json`
- Markdown必須構成:
  1) 先頭に集計（success/blocked/failed）と「blockedをスキップして成功件数を確保した」旨
  2) 対象URL一覧（`status: ok|blocked|failed` 併記）
  3) 各記事の抽出結果（見出し/フック/CTA/頻出フレーズ）
  4) 共通パターン（`ok` のみ）
  5) 差分化の提案（twist案3つ、one_sentence案2つ。`ok` のみ根拠）
  6) “やらないこと”（真似しないポイント）1つ
  7) `blocked` / `failed` は判定理由を短文で明記
- JSON必須キー（固定）:
  - `generated_at` (ISO8601)
  - `success_target` (int)
  - `max_candidates` (int)
  - `candidates_considered` (int)
  - `success_count` (int)
  - `blocked_count` (int)
  - `failed_count` (int)
  - `targets`:
    - `{ url, domain, source, title, status, reason, headings, hook, ctas, frequent_phrases }`
    - `status` は `ok|blocked|failed`
    - `headings` は `[{level:\"h1\"|\"h2\"|\"h3\", text}]`
    - `frequent_phrases` は `[{term, count}]`
  - `common_patterns` (string[])
  - `twist_candidates` (string[]; 3件)
  - `one_sentence_candidates` (string[]; 2件)
  - `dont_copy` (string[])

# Guardrails
- 引用は短く（要点は自分の言葉で要約）。長文転載は禁止。
- 出力は必ずファイルに残す（後で週次digestに利用する）。
- `blocked` / `failed` を推定本文で埋めない。理由記録と繰り上げを優先する。
- `idea_bank/shortlist.json` が無い場合は入力不足として終了し、次を案内する:
  - `bash scripts/research_refresh.sh`
  - `bash scripts/idea_shortlist.sh`

# How to run
- UIで `/skills` → List skills から competitor-scan を選ぶか、プロンプト内で `$competitor-scan` と書いて起動する。
- 例：
  "$competitor-scan: shortlist上位3件を調査して、Day042のtwist/one_sentence改善案を出し、reports/competitors に保存して"
