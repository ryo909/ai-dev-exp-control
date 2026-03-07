# Showcase Policy

- Showcase Planner は「7本のうち1本を戦略的に目立たせる」ための推奨レイヤー。
- まずは推奨のみを出し、自動適用はしない。
- 候補は `novelty / showcase_potential / implementation_risk / component_fit / competitor_signal_strength / quality_confidence` を加重平均して選ぶ。
- large を毎回固定で選ばず、quality/fallback/competitor signal の状況で slot と target tier を決める。
- 失敗しそうな場合は `fallback_tier_if_needed` を使って安全に落とす（large->medium, medium->small）。
- 判断時は `reports/showcase/showcase_plan_<YYYY-MM-DD>.json|md` と `plans/next_batch_plan.json` の showcase 情報を参照する。
