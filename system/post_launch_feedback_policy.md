# Post-Launch Feedback Policy

## 目的
- Post-Launch Feedback Layer は、公開後の実績を回収し、次週の Strategy / Growth / Launch / Control Tower に返す。
- 今回は collection / normalization / digest までを対象とし、自動投稿や外部送信は行わない。

## なぜ Buffer + manual fallback か（無料前提）
- 無料運用で継続しやすく、現実的に回収可能な導線を優先するため。
- X API を使わずに post-level metrics を扱うため。
- UI変更やログイン依存で browser回収が崩れても、manual import で data continuity を維持するため。

## source priority
1. Buffer browser collection（Playwright, best-effort）
2. `imports/feedback/` の manual import（JSON/CSV/TSV）
3. 将来拡張: UTM/GA4（今回は設計メモのみ）

## 3層構造
- raw: `data/feedback/raw/buffer_metrics_<YYYY-MM-DD>.json`
- normalized:
  - `data/feedback/normalized/post_metrics_<YYYY-MM-DD>.json`
  - `data/feedback/normalized/post_metrics.jsonl`（append）
- digest:
  - `reports/feedback/post_launch_feedback_<YYYY-MM-DD>.json`
  - `reports/feedback/post_launch_feedback_<YYYY-MM-DD>.md`

## browser collection と manual import の役割分担
- browser collection:
  - 主ソース。取得可能なら post text / URL / published_at / metrics を回収。
  - ログイン未済・UI変更・selector破綻は notes 化して継続。
- manual import:
  - 継続性確保のための必須 fallback。
  - 取り込み時に列名揺れを吸収し、normalized へ統合する。

## Launch artifacts との紐付け
- `exports/launch/launch_export_*.json`, `x_queue_*.json`, `make_payload_*.json` を参照。
- `tool_day / channel / post_type / URL / published_at` 近傍で best-effort 対応付け。
- launch_id が無い場合は推定IDを生成して継続する。

## Strategy / Growth / Launch への返し方
- Growth: hook_family / CTA family / channel fit の勝ち負け。
- Launch: hero/secondary/quiet/hold 判断の妥当性。
- Strategy: tool shape / complexity傾向 / showcase運用の当たり外れ。
- learned_rules: 自動採用せず候補として提示。

## best-effort 方針
- 回収失敗・欠損・フォーマット揺れがあっても処理全体を止めない。
- 失敗理由は `collection_notes` / `notes` / digest の `summary.notes` に残す。

## 今後の拡張候補
- Task Scheduler / cron による定期収集
- UTM / GA4 integration
- per-post cohort analysis（24h / 72h / 7d）
- analytics-driven learned_rules auto-preview
