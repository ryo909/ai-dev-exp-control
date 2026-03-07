# Weekly Orchestrator Policy

- 週1運用の基本実行コマンドは `scripts/weekly_orchestrator.sh`。
- 初回は `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all` で実行計画だけ確認する。
- adoption profile は `safe -> balanced -> aggressive` の順に段階導入する。
- THESIS は `reports/weekly/thesis_update_draft_<YYYY-MM-DD>.md` を見て人間が更新する（自動上書きしない）。
- 判断順序は `control_tower -> next_batch_plan -> thesis_update_draft -> weekly_run_report` を推奨。
