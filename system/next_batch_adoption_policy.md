# Next Batch Adoption Policy

- `plans/next_batch_plan.json` は推奨のみで、デフォルトでは自動採用しない。
- 推奨採用は段階的に env で有効化する。
  - `USE_NEXT_BATCH_PLAN=1`
  - `ADOPT_NEXT_BATCH_COMPLEXITY=1`
  - `ADOPT_NEXT_BATCH_COMPONENTS=1`
  - `ADOPT_NEXT_BATCH_ENHANCEMENT=1`
- 推奨を採用した場合も、meta には original と adoption trace を残す。
- 最初の安全運用は以下の順。
  1) complexity だけ採用
  2) components を採用
  3) enhancement を採用
- 週次運用では `scripts/weekly_orchestrator.sh` の adoption profile を通して段階適用する。
