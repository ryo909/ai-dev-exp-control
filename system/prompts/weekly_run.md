# weekly_run (Version: 2026-03-xx)

## 0) Quick checks (must)
- git status -sb
- 現在ブランチ確認（sys-self-improve-pack）
- STATE.json の next_day / post_pending を確認
- reports/weekly_digest.md があれば最初に読む

## 1) Update Thesis (weekly focus)
- shared-context/THESIS.md を開き、末尾の「更新手順（週1テンプレ）」に従って今週の重点を更新
- commit: "chore: update weekly thesis"（必要なら）

## 2) Refresh research signals (best-effort)
- hooks が入っている前提で、resume 実行前に pre_resume が走るが、必要なら手動で:
  - bash scripts/research_refresh.sh
  - bash scripts/idea_shortlist.sh

## 3) Execute weekly run
- bash scripts/resume.sh
  - 失敗したら logs/DayXXX.summary.md を最優先に読んで復旧案

## 4) After run: review outputs
- reports/coverage.md を確認（偏り/重複）
- shared-context/SIGNALS.md と idea_bank/shortlist.json を確認（来週ネタ）
- reports/weekly_digest.md を確認（次週改訂材料）

## 5) Improvement loop (lightweight)
- 気づきがあれば shared-context/FEEDBACK-LOG.md / memory/MEMORY.md に追記案（提案ベースでOK）
- パイプライン修正が必要なら最小差分でパッチ→bash -n→コミット案まで
