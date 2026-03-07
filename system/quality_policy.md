# Quality Policy

- quality evaluator v2 は `manifest -> data-quality-marker -> heuristic` の順で判定する。
- 旧テンプレ（manifest/markerなし）でも heuristic fallback で継続評価できる。
- `selected_components` がある場合は expected を明示し、`expected/rendered/detected` の差分で評価する。
- `missing_components` / `unexpected_components` を quality report に残し、次回の改善候補へ使う。
- score が低くても即自動修正はせず、`plans/candidates/dayNNN_quality_upgrade_candidates.json` に次回改善候補を記録する。
- medium/large は tier期待値未達の場合、`recommendation` と confidence を確認して retry/downgrade を判断する。
- confidence は signal source で決める。
  - manifestあり: `high`
  - markerのみ: `medium`
  - heuristicのみ: `low`
