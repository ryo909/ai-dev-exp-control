# ID Schema Policy

## 目的
- Launch / Export / Feedback を横断追跡できる最低限の ID を統一する。
- 既存構造を壊さず、追記中心で導入する。

## 最低限の ID セット
- `tool_id`: 各ツール識別（例: `day001`）
- `launch_id`: 週次 launch 単位（例: `launch-2026-03-07`）
- `post_id`: queue/published 投稿単位（例: `launch-2026-03-07_day001_x_hero_01`）
- `decision_source`: `launch_pack` / `manual_override` / `inferred_from_launch_export`

## taxonomy（軽量）
- `hook_family`: `instant-clarity` / `surprise` / `relatable` / `worldbuilding` / `utility-first` / `generic`
- `cta_family`: `try-now` / `browse-gallery` / `view-github` / `feedback-welcome` / `read-note` / `generic-cta`
- `post_type`: `hero` / `secondary` / `quiet`（`hold`はlaunch decisionとして保持）

## どの成果物に何を持たせるか
- Launch Pack: `launch_id`, 各toolの`tool_id`, `decision_source`
- Launch Export: `launch_id`, 各toolの`tool_id`, `x_queue.post_id`, `hook_family`, `cta_family`, `post_type`
- Feedback normalized: `launch_id`, `tool_id`, `post_id`, `hook_family`, `cta_family`, `post_type`, `decision_source`
- Feedback digest: `by_tool.tool_id` と launch/export 対応情報

## なぜ strict schema ではなく best-effort か
- 既存artifactの欠損や形式差があるため、一括強制は運用停止リスクが高い。
- 週次運用を止めずに、徐々に ID 充足率を上げる方針を採る。

## retrofitting 方針
- 過去成果物の完全移行は必須にしない。
- 最新生成物から ID を安定付与し、control tower で欠損を可視化する。

## 今後の拡張候補
- launch_id の厳密化（run/session紐付け）
- post_id と published URL の完全対応
- per-channel analytics trace
- decision lineage tracking
