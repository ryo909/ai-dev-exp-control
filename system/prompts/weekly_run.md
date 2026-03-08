# weekly_run prompt (sys-self-improve-pack)

対象repoは `ai-dev-exp-control` のみ。  
破壊的変更は禁止。外部送信は `ALLOW_EXTERNAL_SEND=1` がある場合のみ。

## まず監査
1. `git status -sb`
2. `git branch --show-current`
3. `STATE.json` の `next_day`, `last_make_webhook`, `post_pending` を確認
4. 最新の `reports/healthcheck/*`, `reports/weekly/*`, `reports/publish/*` を確認

## 週1実行
- safe preview（既定）:
  - `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all PUBLISH_MODE=preview bash scripts/weekly_orchestrator.sh`
- 実行（送信なし）:
  - `ADOPTION_PROFILE=safe STAGE=all PUBLISH_MODE=preview bash scripts/weekly_orchestrator.sh`

## publish実行（明示時のみ）
- Xのみ送信:
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=x bash scripts/weekly_orchestrator.sh`
- YouTubeのみ送信:
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=youtube bash scripts/weekly_orchestrator.sh`
- X+YouTube送信:
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=x,youtube bash scripts/weekly_orchestrator.sh`

## チェックポイント
- X は Buffer route / YouTube は Make direct route
- duplicate guard は `day-platform`
- `pending_asset` は送信対象外
- `reports/publish/publish_weekly_summary_<date>.json` に visibility を集約
