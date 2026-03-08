# Healthcheck Policy

## 目的
- 週1運用の preflight で、壊れ・欠損・古さ・追跡断絶を先に可視化する。
- 自動停止より visibility を優先し、人間の判断負荷を下げる。

## なぜ週1運用で重要か
- 実行間隔が空くため、依存切れ・未処理import・artifact鮮度低下を見落としやすい。
- launch/export/feedback chain が切れると学習ループが回らない。

## 何をチェックするか
- repo cleanliness
- required files/directories
- artifact freshness
- launch chain consistency（launch/export/feedback + ID有無）
- imports backlog
- feedback continuity
- browser dependency note（Playwright可否の軽確認）
- pending operational risks

## overall_status
- `ok`: 主要問題なし
- `warn`: 実行可能だが注意点あり
- `attention`: 実行前に確認推奨項目が複数ある

## preflight での位置づけ
- `weekly_orchestrator` の preflight で best-effort 実行し、総評をログ表示する。
- 失敗時も全体を止めず、notes に理由を残す。

## なぜ自動停止しないか
- このrepoは継続運用が最優先で、補助レポートの欠損で本流を止めない設計を採るため。

## 今後の拡張候補
- deeper Playwright checks
- scheduled healthcheck
- stale artifact scoring
- pre-adopt guardrails
