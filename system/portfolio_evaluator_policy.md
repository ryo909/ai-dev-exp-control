# Portfolio Evaluator Policy

## 目的
- Portfolio Evaluator は、各 Day ツールを「公開後の見え方」「ポートフォリオとしての強さ」で評価する。
- 既存 quality evaluator（実装品質/部品実装度）とは役割を分離し、presentation 層の意思決定材料を提供する。

## 評価対象
- STATE / catalog / CATALOG の整合
- repo_url / pages_url の健全性（best-effort）
- README の導線と可読性
- demo の分かりやすさ
- showcase として押し出せるか

## スコア項目
- `link_health`
- `readme_hygiene`
- `demo_clarity`
- `catalog_consistency`
- `showcase_readiness`
- 各項目は `0.0 - 1.0` で算出し、重み付き合成で `total_score` を出す。

## Best-effort 方針
- 外部リンク確認は短タイムアウトで試行し、失敗しても evaluator 全体は停止しない。
- 欠損データ（README欠落、catalog差分、URL不整合）は issue に残して継続する。
- hard fail せず、必ず JSON/MD の評価レポート出力を優先する。

## Quality Evaluator との違い
- quality evaluator: 実装の completeness / tier expectation / component 実装確認
- portfolio evaluator: 公開導線・README・リンク・見せ玉としての見栄え評価

## Control Tower 接続
- 最新 `reports/portfolio/portfolio_eval_*.json` を digest に統合し、
  `improvement_signals` と `next_batch_recommendations.recommended_focus` に反映する。
- 次バッチで「何を作るか」だけでなく「どう見せるか」を同時に最適化する。

## 今後の拡張候補
- screenshot ベースの visual scoring
- README 改善提案の自動生成
- auto-fix candidate（リンク/見出し/導線の半自動修正）
- showcase mode 連携による presentation hardening
