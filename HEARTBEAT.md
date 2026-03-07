# HEARTBEAT
## 目的
- 失敗を「次回からの強さ」に変えるチェックリスト。
- 実際の障害が起きたら、このファイルに “再発防止の手順” を追記する。

## 監視ポイント（手動/自動）
- STATE.json schema validate が通るか
- logs/DayXXX.summary.md の有無（失敗検知）
- research_refresh / shortlist の出力が更新されるか
- coverage が生成されるか

## よくある原因と一次対応（雛形）
- gh auth / token / remote 問題 → gh auth status / remote確認
- npm/npx DL失敗 → validate_jsonはスキップする（既存仕様）
- 途中で止まる → DayXXX.summary.md から再実行手順を切る

## 障害記録（追記して育てる）
- YYYY-MM-DD: (原因/対処/再発防止)
