# Learning Loop Policy

- learning loop は `preview -> backup -> adopt` の順で実施する。
- `safe` は preview のみ、`balanced` は MEMORY/FEEDBACK まで、`aggressive` は SOURCES/learned_rules まで採用する。
- 推奨開始は `balanced` まで。`aggressive` は重複やノイズ混入を確認してから使う。
- `MEMORY` は長期知見、`FEEDBACK` は出力改善、`SOURCES` はネタ元学習、`learned_rules` は事故防止ルールを記録する。
