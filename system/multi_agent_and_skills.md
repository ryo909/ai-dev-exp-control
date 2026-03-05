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
