# Weekly Run

## 基本手順
- まず `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` で計画確認。
- 問題なければ `ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` を実行。

## 今週の運用方針
- adoption profile: safe
- preview を先に確認し、adopt は必要時のみ有効化する
- showcase slot が next_batch_plan にある週は、その1本だけ large / competitor enhancement を優先候補として検討する（自動適用しない）

## 推奨コマンド例
- `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh`
- `ADOPTION_PROFILE=balanced STAGE=preview bash scripts/weekly_orchestrator.sh`
