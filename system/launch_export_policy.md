# Launch Export Policy

## 目的
- Launch Export Layer は Launch Pack の判断を、外部実務に渡しやすい handoff artifact に変換する。
- 今回は送信ではなく export までを対象にする。

## Launch Export Layer が扱う問い
- hero/secondary/quiet/hold をどの形式で渡すか
- X / note / gallery / Make 向けにどの情報を最小セットで揃えるか
- 手動最終確認の負荷をどう下げるか

## 入力ソース（best-effort）
- 優先: `reports/launch/launch_pack_*.json`
- 補助: growth/strategy/portfolio/evidence/reality/showcase/control_tower reports, `STATE.json`, `catalog/catalog.json`
- 欠損入力は `inputs_used` と `notes` に明示して継続する。

## 出力構造
- `exports/launch/launch_export_<YYYY-MM-DD>.json`
- `exports/launch/launch_export_<YYYY-MM-DD>.md`
- 補助出力（可能なら）:
  - `exports/launch/make_payload_<YYYY-MM-DD>.json`
  - `exports/launch/note_seed_<YYYY-MM-DD>.md`
  - `exports/launch/gallery_entries_<YYYY-MM-DD>.json`
  - `exports/launch/x_queue_<YYYY-MM-DD>.json`

## Launch Pack との違い
- Launch Pack: 戦略・発信・品質判断を統合した「何をどう出すか」
- Launch Export: その判断を「外部運用へ渡せる形式」に整形

## 送信までやらない理由
- 既存OSは推奨生成と実行を分離し、安全性と監査可能性を優先するため。

## hero / secondary / quiet / hold の扱い
- hero: 最優先の投稿/導線/コピーを厚めに出す
- secondary: 簡潔な投稿候補と gallery 連携向け
- quiet: 一覧掲載向け短文中心
- hold: 修正項目を明示し、実行対象から除外

## チャネル位置づけ
- X: short hook + CTA + URL
- note: title/intro/outline seed
- gallery: 一覧導線向け短文
- Make: 将来連携向け中間payload

## best-effort 方針
- 欠損入力や外部状態に依存せず、最低限の export artifact を必ず生成する。

## 今後の拡張候補
- Buffer-ready CSV renderer
- Make webhook auto-send
- note draft auto-seed
- channel-specific renderers
- post-launch analytics feedback ingestion
