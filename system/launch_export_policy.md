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

## Make webhook payload 契約（publish_payload.v2）
- `make_payload.publish_items` を webhook `posts` の正本として扱う。
- `platform` でルーティングし、各 route は必須キーで filter/map する。

### X item 必須
- `day`（`"009"` 形式）
- `platform`（`"x"`）
- `text`
- `dueAt`（ISO8601 / `+09:00`）

### YouTube item（将来拡張）
- `day`
- `platform`（`"youtube"`）
- `title`
- `description`
- `videoUrl`
- `thumbnailUrl`（空文字許容）
- `dueAt`
- `privacy`（例: `public`）
- `madeForKids`（bool）
- `notifySubscribers`（bool）

## Publish ルーティング責務（固定）
- X: Buffer route（Make内で Buffer module に接続）
- YouTube: Make direct YouTube route（Buffer は使わない）

### Make 設定（X）
- filter: `platform = x` かつ `text` exists かつ `dueAt` exists
- Buffer module:
  - Text = `2.text`
  - Date scheduled = `2.dueAt`

### Make 設定（YouTube direct）
- filter: `platform = youtube` かつ `title` exists かつ `videoUrl` exists かつ `dueAt` exists
- HTTP - Download a file:
  - URL = `2.videoUrl`
- YouTube module:
  - title = `2.title`
  - description = `2.description`
  - scheduled_at = `2.dueAt`
  - privacy / madeForKids / notifySubscribers / thumbnailUrl を必要に応じて対応づけ

## YouTube readiness 定義
- `ready`: 必須（title/description/videoUrl/dueAt）が揃い、publish対象に含めてよい
- `pending_asset`: 主に `videoUrl` 欠損。動画アセット待ち
- `blocked`: 必須項目の複数欠損や運用条件未達
- `invalid`: URL/時刻形式などの値が不正

`send_make_payload.sh` は YouTube を `readiness=ready` かつ `videoUrl` ありの item のみ送信対象に含める。

## 重複判定キー（publish）
- duplicate guard は `day` 単位ではなく `day-platform` 単位で判定する。
- 例:
  - `009-x`
  - `009-youtube`
  は別ターゲットとして扱う。
- `send_make_payload.sh` は `last_make_webhook.posted_targets` を優先参照し、旧データしかない場合は `posted_days × target_platforms`（未設定時は `x`）で後方互換判定する。

## dueAt 生成ルール（既定）
- policy file: `system/publish_schedule_policy.json`
- timezone: Asia/Tokyo（`+09:00`）
- base date: export/build 実行日の `--date`
- start offset: `+1 day`
- weekly slots（X / YouTube 共通の既定）:
  - mon `21:00`
  - tue `08:30`
  - wed `12:10`
  - thu `09:00`
  - fri `08:30`
  - sat `10:00`
  - sun `21:00`
- Day順（昇順）に対象日へ割り当て、各日の曜日スロットを `dueAt` に反映する。

## YouTube videoUrl の入力経路
- 優先: `imports/publish/youtube_video_handoff_<YYYY-MM-DD>.json`
- 次点: `imports/publish/youtube_video_handoff_latest.json`
- fallback: `STATE.json` の day エントリ内 `youtube_url / video_url` 系キー
- テンプレ: `imports/publish/youtube_video_handoff.example.json`
- schema: `schemas/youtube_video_handoff_schema.json`

### handoff 優先順位
1. `youtube_video_handoff_<YYYY-MM-DD>.json`
2. `youtube_video_handoff_latest.json`
3. `youtube_video_handoff.json`
4. `exports/launch/youtube_upload_handoff_<YYYY-MM-DD>.json`
5. `exports/launch/youtube_upload_handoff_*.json` 最新
6. `STATE.json` fallback

`build_launch_exports.py` は上記候補を段階マージし、`videoUrl` が placeholder の場合は後段ソースの実URLで補完する。

### handoff 半自動更新（推奨）
- 動画生成後に latest handoff を更新:
  - `python3 scripts/promote_youtube_handoff.py --date YYYY-MM-DD --days 009,010,...`
- このコマンドは `imports/exports/STATE` を自動マージし、`videoSource` と `assetStatus` を付与する。
- unresolved は `unresolved_days` と `assetStatus=pending_asset` で明示される。

## 運用コマンド（例）
- handoff 雛形更新:
  - `python3 scripts/generate_youtube_handoff_template.py --date YYYY-MM-DD --days 009,010,...`
- handoff 自動昇格（動画生成成果を反映）:
  - `python3 scripts/promote_youtube_handoff.py --date YYYY-MM-DD --days 009,010,...`
- preview:
  - `python3 scripts/build_launch_exports.py --date YYYY-MM-DD --days 009,010,...`
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --preview --platforms x,youtube`
- X のみ送信:
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --platforms x --batch-id manual-<timestamp>-x`
- YouTube のみ送信（videoUrl 供給後）:
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --platforms youtube --batch-id manual-<timestamp>-yt`
- X+YouTube 送信（videoUrl 供給後）:
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --platforms x,youtube --batch-id manual-<timestamp>-x-yt`
- 再送（同じ day-platform を再送）:
  - `bash scripts/send_make_payload.sh --date YYYY-MM-DD --days 009,010,... --webhook-only --platforms x,youtube --force --batch-id manual-<timestamp>-rerun`

## publish report 監視ポイント
- `reports/publish/publish_preview_*.json`
  - `target_platforms`
  - `x_ready_count`
  - `youtube_ready_count`
  - `youtube_missing_video_count`
  - `dueAt_summary`
  - `requested_targets` / `send_targets` / `overlap_targets`（day-platform）
- `reports/publish/make_webhook_send_*.json`
  - `sent_targets`
  - `sent_post_count`
  - `skipped_summary`
  - `duplicate_key_mode`

## best-effort 方針
- 欠損入力や外部状態に依存せず、最低限の export artifact を必ず生成する。

## 今後の拡張候補
- Buffer-ready CSV renderer
- Make webhook auto-send
- note draft auto-seed
- channel-specific renderers
- post-launch analytics feedback ingestion
