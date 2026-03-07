# Agent Topology (ai-dev-exp-control)

この文書は、現行OSを「会話AIの人数」ではなく「責務と入出力を持つ専門役」として定義する。
既存 script/stage/report を multi-role topology として可視化し、改善時の接続点を明確化する。

## 1) Scout
- 目的: 市場信号を収集し、再利用可能な差分材料を作る。
- 主な入力: RSS/feeds, source targets, 過去の競合レポート。
- 主な出力: `shared-context/SIGNALS.md`, `reports/competitors/competitor_scan_*`。
- 対応実装: `scripts/research_refresh.sh`, `scripts/idea_shortlist.sh`, competitor scan 系。
- 実装状態: 明示実装済み。
- 弱点/未実装: blocked source 時の代替探索はあるが、業界別の深掘りテンプレは弱い。

## 2) Strategist
- 目的: 週次の勝ち筋・重点を定義し、次バッチ方針を揃える。
- 主な入力: control tower, THESIS, shortlist, showcase/portfolio/growth briefs。
- 主な出力: `shared-context/THESIS.md`, thesis draft/preview。
- 対応実装: `build_control_tower_digest.py`, `build_thesis_update_draft.py`。
- 実装状態: 明示実装済み。
- 弱点/未実装: 戦略比較（A/B方針）を明示的に比較する層は未実装。

## 3) Architect
- 目的: 7本の complexity/component/fallback 配分を安全に設計する。
- 主な入力: tier performance, quality/fallback, showcase recommendation。
- 主な出力: `plans/next_batch_plan.json`, fallback/enhanced candidates。
- 対応実装: `build_next_batch_plan.py`, `write_fallback_plan.py`, `build_showcase_plan.py`。
- 実装状態: 明示実装済み。
- 弱点/未実装: 配分ルールの長期最適化（季節性・連続性）は弱い。

## 4) Builder
- 目的: 1日1本を実装し build/deploy/post まで進める。
- 主な入力: selected day plan, meta, templates。
- 主な出力: `.workdays/*`, day repo, deploy/post status。
- 対応実装: `run_day.sh`, `run_batch.sh`, `resume.sh`（template側と境界）。
- 実装状態: 明示実装済み（実装本体は template repo 側依存）。
- 弱点/未実装: テンプレ多様化の自動選択は限定的。

## 5) Critic
- 目的: 品質・リスク・fallback必要性を判定して安全運用を維持する。
- 主な入力: build artifacts, quality markers/manifest, fallback plans。
- 主な出力: `reports/quality/day*_quality.json`, upgrade/fallback 提案。
- 対応実装: `evaluate_build_quality.py` v2。
- 実装状態: 明示実装済み。
- 弱点/未実装: UI/UX定性評価は限定的（構造的検出が中心）。

## 6) Portfolio
- 目的: 公開後の見え方（README/Pages/catalog整合）を評価する。
- 主な入力: `STATE.json`, `catalog/catalog.json`, `CATALOG.md`, `.workdays` README。
- 主な出力: `reports/portfolio/portfolio_eval_*.json|md`。
- 対応実装: `evaluate_portfolio.py`。
- 実装状態: 明示実装済み。
- 弱点/未実装: スクリーンショットや第一印象の視覚評価は未実装。

## 7) Growth
- 目的: どう見せるか/どう刺すか/どう発信するかを recommendation として提示する。
- 主な入力: next_batch_plan, showcase/control_tower/competitor, portfolio(optional), STATE/catalog。
- 主な出力: `reports/growth/growth_brief_*.json|md`, launch方針。
- 対応実装: `build_growth_brief.py`（report stage 接続）。
- 実装状態: 今回明示実装。
- 弱点/未実装: 自動投稿連携やチャネル別自動最適化は未実装（計画層のみ）。

## Topology運用メモ
- `weekly_orchestrator.sh` は role 間の handoff を担うランナーであり、各 role は best-effort artifact を優先生成する。
- 既存OSでは「自動採用」ではなく「推奨生成→人間判断」が原則。
- 新規レイヤー追加時は、既存出力を壊さず `improvement_signals` と `recommended_focus` へ増分統合する。
