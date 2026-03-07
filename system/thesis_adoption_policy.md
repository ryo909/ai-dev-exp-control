# Thesis Adoption Policy

- THESIS 更新は `preview -> backup -> adopt` の順で行う。
- デフォルトは preview のみで、`ADOPT_THESIS_DRAFT=1` のときだけ採用する。
- 採用時は必ず `backups/thesis/` にバックアップを保存する。
- safe: previewのみ / balanced: THESIS採用まで / aggressive: THESIS+weekly_run採用。
