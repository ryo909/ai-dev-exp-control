# Component Pack Policy

- complexity_tier の厚みは、危険な構造変更ではなく安全な再利用部品の追加で作る。
- `selected_components` は `complexity_profiles.json` の `preferred_components` から deterministic に選ぶ。
- small は 1部品、medium は 2部品、large は 3部品を推奨上限の目安にする。
- 追加候補は `reason_panel`, `sample_inputs`, `local_storage`, `comparison_view`, `history_panel`, `export_suite`, `step_ui` を中心に使う。
