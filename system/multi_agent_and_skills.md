# Multi-Agent and Skills

- Multi-agent ON は UI の `/experimental` もしくは `codex features enable multi_agent` で有効化できる。
- roles の用途:
  - `explorer`: read-only探索（コード/STATE/ログの要点抽出）
  - `reviewer`: read-only品質監査（coverage/重複/meta品質/運用リスク）
  - `docs_researcher`: read-only一次情報確認（OpenAI/Codex/MCP/skills/multi-agent）
  - `worker`: 最小差分の実装担当
  - `monitor`: 待機・進捗監視担当
- Skills は UI の `/skills` またはプロンプトの `$competitor-scan` で起動する。
- `competitor-scan` の出力先は `reports/competitors/`。
- `competitor-scan` は `competitor_scan_<YYYY-MM-DD>_shortlist.md` と `competitor_scan_<YYYY-MM-DD>_shortlist.json` を同時に出力する。
- Cloudflare など verification 系は `blocked` として記録し、スキップしながら `success_target` 件の `ok` を確保する。
- `run_day.sh` は最新 `competitor_scan_*_shortlist.json` から `plans/candidates/dayNNN_enhanced_candidates.json` を生成する（best-effort）。既定は候補保存のみで、`ADOPT_ENHANCED_PLAN=1` のときだけ recommended candidate を採用する。
- `run_day.sh` は `complexity_tier`（small/medium/large）を7本配分で決定し、`run_batch.sh` は失敗時に `plans/candidates/dayNNN_fallback_plan.json` を best-effort で出力する。
