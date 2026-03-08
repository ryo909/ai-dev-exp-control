# Strategy Policy

## 目的
- Strategy Brief は、週次の「勝ち筋・避けるべき方向・次バッチ思想」を明文化する framing layer。
- 既存の control tower / showcase / next_batch / THESIS に分散した判断を、上書きせずに整理する。

## Strategy Brief が扱う問い
- 今週は何で勝ちに行くか
- 何を意図的に捨てるか
- showcase をどう意味づけるか
- 次バッチの complexity/component/enhancement/fallback をどんな思想で使うか

## 入力ソース（best-effort）
- 優先: `shared-context/SIGNALS.md`, `idea_bank/shortlist.json`, `reports/competitors/*`, `reports/control_tower/*`, `reports/showcase/*`, `plans/next_batch_plan.json`, `shared-context/THESIS.md`, `system/prompts/weekly_run.md`
- 補助: `reports/growth/*`, `reports/portfolio/*`, quality/fallback/learning 系、identity/memory/feedback
- 欠損入力があっても Strategy Brief 全体を止めない。

## 出力構造
- `reports/strategy/strategy_brief_<YYYY-MM-DD>.json`
- `reports/strategy/strategy_brief_<YYYY-MM-DD>.md`
- JSON は `summary / inputs_used / strategic_direction / batch_guidance / slot_recommendations / thesis_candidates / decision_rules` を含む。

## Strategist と他roleの違い
- Scout: 市場信号の収集
- Architect: slot配分と実装計画
- Growth: 発信・訴求の具体化
- Portfolio: 公開物の見え方評価
- Strategist: これらを束ねて「今週の攻め方」を定義

## THESIS / next_batch_plan / showcase / control tower との関係
- THESIS: 週次宣言（最終記述先）
- next_batch_plan: slot別の具体推奨
- showcase planner: 見せ玉選定
- control tower: 全体統合判断
- Strategy Brief: 上記の間をつなぐ思想整理（推奨のみ）

## best-effort 方針
- ファイル欠損・入力不足時は `inputs_used` で明示し、低信頼で継続出力する。
- 自動採用・自動上書きは行わない。

## 今後の拡張候補
- explicit thesis diff scoring
- slot-by-slot strategic simulation
- showcase-only strategic debate
- growth / portfolio / strategy unified launch thesis
