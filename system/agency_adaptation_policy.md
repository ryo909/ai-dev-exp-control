# Agency Adaptation Policy

## なぜ agency-agents をそのまま移植しないか
- Claude Code向けの大量エージェント常駐は、Codex運用では過剰な分岐と同期コストを生みやすい。
- このrepoは週次バッチOSが中心であり、人格より artifact contract が安定運用に効く。

## Codexでの再構成方針
- `AGENTS.md`: repo全体ルール（憲法）
- `system/agents/*.md`: 役割仕様（Agent Card）
- `.agents/skills/*`: task-specific capability
- `scripts + reports`: 実働成果物

## role count より output contract を優先する理由
- 役を増やすだけでは品質が上がらず、成果物の検証可能性が下がる。
- 必須入力・必須出力・成功基準を固定すると、best-effortでも比較可能になる。

## personality-first を避ける理由
- 本repoは自動運用比率が高く、表現差より再現性が重要。
- personality中心設計は評価軸が曖昧になり、改善ループが弱くなる。

## 追加役を選んだ理由
- `Evidence Collector`: quality/portfolioで拾いにくい visual evidence を補完
- `Reality Checker`: quality+portfolio+evidence を統合して release gate 判断を補助
- `Whimsy Injector`: showcase専用で記憶に残る演出案を限定適用
- `Studio Producer`: 既存orchestrator/control towerの統合責任を明文化

## なぜ Whimsy を showcase 限定にするか
- 常時適用すると clarity を壊しやすく、small/mediumの安定運用と衝突する。
- 見せ玉1本に限定すれば、演出効果と運用コストのバランスが取れる。

## multi-agent を局所利用にする理由
- 常時並列は観測コストが高く、失敗点の切り分けが難しい。
- pre-build/post-buildの限定フェーズで使うと責務が明確になる。

## 今後の拡張候補
- launch pack（strategy/growth/portfolio/realityの統合）
- screenshot-based portfolio scoring 強化
- strategy/growth/portfolio unified review
- showcase-only mini debate
