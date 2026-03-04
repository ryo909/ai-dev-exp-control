# AGENTS.md — ai-dev-exp-control
## Startup routine
1) identity/SOUL.md / identity/USER.md / identity/IDENTITY.md を読む
2) shared-context/THESIS.md / shared-context/FEEDBACK-LOG.md / memory/MEMORY.md を読む
3) STATE.json を読み、next_day/post_pending を把握
4) reports/weekly_digest.md があれば最初に読む

## Rules
- 最小差分。破壊的変更禁止。diff提示してから。
- 失敗は logs/DayXXX.summary.md が最優先の真実。
- best-effortタスク（digest/統計/ログ）は失敗しても止めない。
- STATE/metaはスキーマ検証を尊重（既存仕組みを壊さない）。
