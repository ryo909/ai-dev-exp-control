# Agent Card Schema

目的: 役割を人格ではなく output contract として定義し、Codex運用で再利用できる形に揃える。

## 共通フォーマット
- `name`
- `purpose`
- `when_to_use`
- `primary_inputs`
- `primary_outputs`
- `workflow`
- `critical_rules`
- `success_metrics`
- `handoff_targets`
- `anti_patterns`
- `codex_mapping`

## 記述ルール
- 抽象論より、入出力ファイルと判定基準を優先する。
- 「何をやらないか」を必ず書く。
- `success_metrics` は測定可能な指標（生成ファイル数、必須キー充足、判定数など）にする。
- `codex_mapping` では以下を明示する。
  - `AGENTS.md` で担うルール
  - `Skill` で担う再利用手順
  - `script/report` で担う実働
  - `multi-agent` を使う場合の局所条件

## 例: codex_mapping
- AGENTS.md: 役割の起動条件・禁止事項
- Skill: 手順テンプレ（SKILL.md）
- script/report: 定期的に生成する成果物
- multi-agent: 同時に回す必要があるときだけ局所起動
