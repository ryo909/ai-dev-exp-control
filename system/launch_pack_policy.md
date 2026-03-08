# Launch Pack Policy

## 目的
- Launch Pack は strategy/growth/portfolio/evidence/reality を束ね、実務で使える launch 推奨パックを生成する。
- 自動投稿ではなく human-in-the-loop の意思決定支援を目的とする。

## Launch Pack が扱う問い
- 今週どのツールを hero として前に出すか
- secondary / hold / quiet catalog をどう分けるか
- どのチャネルでどう出し分けるか
- どの文面・proof point・CTAが実用的か

## 入力ソース（best-effort）
- 優先: strategy/growth/portfolio/evidence/reality/showcase/control_tower reports
- 補助: next_batch_plan, STATE, catalog, competitors, quality
- 欠損入力があっても `inputs_used` で明示して出力を継続する。

## 出力構造
- `reports/launch/launch_pack_<YYYY-MM-DD>.json`
- `reports/launch/launch_pack_<YYYY-MM-DD>.md`
- hero launch pack, by_day decision, distribution mix を含む。

## 既存レイヤーとの関係
- Strategy: 方向性
- Growth: 発信フック/コピー
- Portfolio: 公開物の健全性
- Evidence: 見た目の証拠
- Reality: release gate
- Launch Pack: 上記を束ねた最終 packaging

## decision 区分
- `launch_now`: 今週押し出してよい
- `launch_with_notes`: 軽修正前提で出せる
- `hold`: 今押し出すと危険
- `quiet_catalog`: 強く押さず一覧掲載向き

## 自動投稿をやらない理由
- 既存OSは推奨生成と人間判断を分離しているため。
- 投稿実行の失敗リスクより、判断材料の透明性を優先するため。

## best-effort 方針
- report欠損、リンク失敗、評価欠損でも Launch Pack 全体は出力する。
- 欠損理由は `inputs_used` / `issues` / `risk_notes` に残す。

## 今後の拡張候補
- Buffer / Make export
- launch copy auto-export
- image prompt seed generation
- note draft seed
- per-channel template rendering
