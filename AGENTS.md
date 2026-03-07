# AGENTS.md — ai-dev-exp-control
## Startup routine
1) identity/SOUL.md / identity/USER.md / identity/IDENTITY.md を読む
2) shared-context/THESIS.md / shared-context/FEEDBACK-LOG.md / memory/MEMORY.md を読む
3) STATE.json を読み、next_day/post_pending を把握
4) reports/weekly_digest.md があれば最初に読む

## Rules
- 最小差分。破壊的変更禁止。diff提示してから。
- 失敗は logs/DayXXX.summary.md が最優先の真実。
- best-effortタスク（digest/統計/ログ）は失敗しても止めない。
- STATE/metaはスキーマ検証を尊重（既存仕組みを壊さない）。

## MCP Usage Rules（品質安定のための必須ルール）
- OpenAI製品やCodexの仕様確認が必要なときは、必ず `openaiDeveloperDocs` MCP を使って一次情報を確認してから結論を書く
  - 例：codex mcp / exec / config / sandbox / approval / multi-agent など
- ライブラリ/フレームワーク実装（React/Vite/Supabase/Playwright等）で “最新の正しい使い方” が必要なときは `context7` を優先する
  - 実装で迷走しそうなら、まずcontext7で公式用法を確認→最小実装→テスト
- 競合調査・構成抽出・特定記事/ページの要点抽出は `playwright` を使う
  - 最低限：見出し構造（H1-H3）、冒頭フック、CTA、章立て、頻出キーワードを抽出
  - 目的：twistの差分を1文で書ける材料にする
- 長くて複雑な改善（パイプライン強化、複数ファイル改修、手順設計）は `sequentialthinking` を使って
  - ①分解→②実行→③検証→④反省点 の順で進める
- `memory` MCPは実験的に使用可。ただしこのrepoの“正”はファイルベース（memory/MEMORY.md / memory/daily）である
  - MCP memory に保存した重要事項は、週次で必ず MEMORY.md にも転記（ファイルが真実）

## MCP Safety
- MCPは必要なときだけ呼ぶ（増やしすぎない）
- 外部認証や秘密情報が必要なMCPは repo同梱しない（別途手順化して人間認可が必要）

## Agent Cards / Skills
- 役割分担は `system/agents/*.md` の Agent Card を参照する（詳細はカード側、AGENTS.mdは憲法に留める）。
- Skills は task-specific capability として使い、人格ロールの代替にしない。
- specialized work は可能な限り report artifact を残す（例: quality/portfolio/growth/strategy/evidence/reality）。
- Launch Pack は Studio Producer / Growth / Portfolio / Reality Checker の交点にある集約artifactとして扱う。
- personality より deliverable（入力契約・出力契約・判定基準）を優先する。
- Whimsy Injector は showcase 専用でのみ許可する。通常dayでは適用しない。
- 大量ロール常駐化はしない。multi-agent は局所利用に限定する。
- 推奨 multi-agent 利用箇所:
  - pre-build: Scout + Strategist + Architect
  - post-build: Evidence Collector + Portfolio + Growth + Reality Checker
