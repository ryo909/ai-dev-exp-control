# Codex MCP (project-scoped)

このリポジトリは `.codex/config.toml` に「秘密情報なし」のMCPサーバを同梱する。

## 同梱MCP
- openaiDeveloperDocs: OpenAI公式ドキュメント参照（仕様確認・ハルシネ防止）
- context7: ライブラリ/SDKの最新ドキュメント参照（実装精度向上）
- playwright: ブラウザ調査（競合調査・構成抽出・引用元確認）
- sequentialthinking: 複雑タスクの段階分解（計画→実行→検証の安定）
- memory: ローカル永続メモリ（保存先: mcp_state/memory.json を試行）

## 確認コマンド
- `codex mcp list`
- `codex` 起動後 `/mcp`

## 注意
- project-scoped MCP設定は初回に “trusted project” の確認が出ることがある（許可する）
- context7/playwright は初回に npx が依存DLするため、ネットワーク状況で失敗することがある
- 失敗してもCodex全体が起動不能にならないよう required を使っていない
