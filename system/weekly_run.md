# Weekly Run

## 基本手順
- まず `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` で計画確認。
- 問題なければ `ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` を実行。

## 今週の運用方針
- adoption profile: safe
- preview を先に確認し、adopt は必要時のみ有効化する

## 推奨コマンド例
- `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh`
- `ADOPTION_PROFILE=balanced STAGE=preview bash scripts/weekly_orchestrator.sh`
