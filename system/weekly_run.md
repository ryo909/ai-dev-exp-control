# Weekly Run

## 固定方針
- gallery は週1フローで apply まで行う。
- X は Buffer 経由、YouTube は Make direct で送信する。
- default は safe（preview）で、外部送信は `ALLOW_EXTERNAL_SEND=1` の明示時のみ。
- duplicate guard は `day-platform` 単位。

## 代表コマンド
- weekly safe preview（推奨）
  - `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all PUBLISH_MODE=preview bash scripts/weekly_orchestrator.sh`
- weekly safe 実行（送信なし）
  - `ADOPTION_PROFILE=safe STAGE=all PUBLISH_MODE=preview bash scripts/weekly_orchestrator.sh`
- weekly + gallery apply only
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=preview PUBLISH_PLATFORMS=x,youtube PUBLISH_APPLY_GALLERY=1 bash scripts/weekly_orchestrator.sh`
- weekly with X send only
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=x PUBLISH_BATCH_ID_PREFIX=weekly-x bash scripts/weekly_orchestrator.sh`
- weekly with YouTube send only
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=youtube PUBLISH_BATCH_ID_PREFIX=weekly-yt bash scripts/weekly_orchestrator.sh`
- weekly with X + YouTube send
  - `ADOPTION_PROFILE=safe STAGE=publish PUBLISH_MODE=send ALLOW_EXTERNAL_SEND=1 PUBLISH_PLATFORMS=x,youtube PUBLISH_BATCH_ID_PREFIX=weekly-publish bash scripts/weekly_orchestrator.sh`

## publish 単体コマンド
- X preview
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --preview --platforms x`
- YouTube preview
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --preview --platforms youtube`
- handoff 更新後の再preview
  - `python3 scripts/promote_youtube_handoff.py --date YYYY-MM-DD --days 009,010,...`
  - `python3 scripts/build_launch_exports.py --date YYYY-MM-DD --days 009,010,...`
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --preview --platforms x,youtube`

## 観測ポイント
- `reports/publish/publish_weekly_summary_<YYYY-MM-DD>.json`
- `reports/publish/publish_preview_*.json`
- `reports/publish/make_webhook_send_*.json`
- `reports/weekly/weekly_run_report_<YYYY-MM-DD>.json`
