# Showcase Planner Policy

- showcase planner は `plans/next_batch_plan.json` を入力に、次バッチの「見せ玉候補」を `reports/showcase/showcase_plan_<YYYY-MM-DD>.json|md` に提案する。
- 出力は advisory（推奨のみ）で、自動採用はしない。
- 週次運用では `weekly_orchestrator.sh` の intel stage で best-effort 生成する。
- 品質が不安定な週は `next_batch_adoption_policy` の safe/balanced を優先し、showcase候補は人手判断で採用する。
