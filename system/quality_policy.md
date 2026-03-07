# Quality Policy

- quality evaluator は lightweight heuristic で判定する（厳密解析はしない）。
- complexity_tier は部品数で厚みを上げる。コード量で競わない。
- score が低くても即自動修正はせず、`plans/candidates/dayNNN_quality_upgrade_candidates.json` に次回改善候補を記録する。
- medium/large は tier 期待値を満たせなかった場合、upgrade候補を必ず確認して次回に反映する。
