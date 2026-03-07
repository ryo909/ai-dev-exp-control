# Weekly Orchestrator Policy

- 週1運用の基本実行コマンドは `scripts/weekly_orchestrator.sh`。
- 初回は `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all` で実行計画だけ確認する。
- adoption profile は `safe -> balanced -> aggressive` の順に段階導入する。
- 更新は `preview -> backup -> adopt` の順で行い、無条件上書きはしない。
- `safe` は preview のみ、`balanced` は THESIS 採用まで、`aggressive` は THESIS + weekly_run 採用までを許可する。
- THESIS は `reports/weekly/thesis_update_draft_<YYYY-MM-DD>.md` と `reports/weekly/thesis_preview_<YYYY-MM-DD>.md` を見て採用判断する。
- 判断順序は `control_tower -> next_batch_plan -> thesis_update_draft -> weekly_run_report` を推奨。
