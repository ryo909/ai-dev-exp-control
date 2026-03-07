# Fallback Policy

## 初期方針
- 失敗時は自動再試行せず、次の安全案を `plans/candidates/dayNNN_fallback_plan.json` に記録する。
- 判定と復旧の起点は `logs/DayNNN.summary.md` と fallback plan の2点に置く。

## tierダウンルール
- `large -> medium`
- `medium -> small`
- `small -> small`（再試行推奨なし）

## なぜ自動再試行しないか
- 初期は成功率保護を優先し、過剰な自動化で連鎖失敗を増やさないため。

## 将来の自動再試行条件
- fallback plan の採用成功率が安定して高い
- 失敗分類（依存不通/実装不整合）の誤判定率が低い
- 明示フラグ（例: `ENABLE_COMPLEXITY_FALLBACK=1`）でのみ有効化
