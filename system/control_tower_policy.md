# Control Tower Policy

- Control tower は自動適用ではなく、signals/coverage/competitor/quality/fallback を統合した意思決定支援レイヤー。
- `plans/next_batch_plan.json` は推奨のみで、まず人間または weekly run が採用判断を行う。
- complexity mix は固定配分ではなく、tier成績（quality/fallback）ベースの推奨へ段階移行する。
- day decision summary は以下の意味で使う。
  - `keep`: 現状維持で継続
  - `enhance`: enhancement候補を優先採用
  - `downgrade`: complexityを一段落として再挑戦
  - `retry_later`: 失敗ログが重く、先に安定化が必要
- `next_batch_plan` の実運用は `system/next_batch_adoption_policy.md` の段階フラグで行い、初期は opt-in のみ。
- 週次の実行順は `scripts/weekly_orchestrator.sh` を使い、stage分割で安全に進める。
- quality evaluator v2 の `confidence` と `missing_components` 集計を tier_performance/improvement_signals に反映し、次週の component 強化優先度を決める。
