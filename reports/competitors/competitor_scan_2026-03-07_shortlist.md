# Competitor Scan (2026-03-07, shortlist)

## 1) 対象URL一覧

- 対象元: `idea_bank/shortlist.json` の先頭3件
- URL 1: https://buttondown.com/creativegood/archive/ai-and-the-illegal-war/
- URL 2: https://www.science.org/content/article/can-wealthy-family-change-course-deadly-brain-disease
- URL 3: https://github.com/golang/go/issues/62026

## 2) 各記事の抽出結果（見出し/フック/CTA）

### URL 1: buttondown.com / AI and the illegal war
- 取得ステータス: 取得成功
- Title: `AI and the illegal war`
- H1-H3:
  - H1: `Creative Good`, `AI and the illegal war`
  - H2: `Search`
  - H3: `Unsubscribe`, `Almost there...`
- 冒頭フック（最初の段落要点）:
  - 強い引用で始めて、政治的・倫理的な問題提起に即接続する導入。
- CTA:
  - `Subscribe`, `join Creative Good`, `Unsubscribe`
- 頻出フレーズ（上位）:
  - `military`, `oligarchs`, `stupid`, `current`, `occupant`, `subscribe`

### URL 2: science.org / Can a wealthy family change the course of a deadly brain disease?
- 取得ステータス: **推定**（Cloudflareのbot/security verificationページが表示され本文未取得）
- Title: `Just a moment...`
- H1-H3:
  - H1: `www.science.org`
  - H2: `Performing security verification`, `Verification successful. Waiting for www.science.org to respond`
  - H3: なし
- 冒頭フック（推定）:
  - 本文は取得不能。タイトルから、希少/致死性疾患に対して「資本で研究進行を変えられるか」を問う科学記事導入と推定。
- CTA（推定）:
  - 本文ページのため明確な購読CTAは確認不可（サイト上では購読/ログイン導線が一般的と推定）。
- 頻出フレーズ（取得画面ベース）:
  - `security`, `verification`, `website`, `bots`

### URL 3: github.com / Go issue #62026 (UUID package proposal)
- 取得ステータス: 取得成功
- Title: `proposal: crypto/uuid: add API to generate and parse UUID · Issue #62026 · golang/go`
- H1-H3:
  - H1: `proposal: crypto/uuid: add API to generate and parse UUID #62026`（ほかにGitHub UI由来見出しあり）
  - H2: `Description`, `Activity`, `Metadata`（ほかUI見出しあり）
  - H3: コメント時系列見出し（`... commented on ...`）
- 冒頭フック（最初の本文要点）:
  - 標準ライブラリにUUID生成/解析API（v3/v4/v5）を追加したい、という明確な提案から開始。
- CTA:
  - `comment` / `reply` 相当の議論参加導線（Issue文脈）
- 頻出フレーズ（上位）:
  - `uuid`, `generator`, `proposal`, `type`, `interface`, `func`, `error`, `standard`

## 3) 共通パターン

- 冒頭で主張を即提示する（問題提起 or 提案文の即出し）。
- CTAは「購読」「議論参加」など、次の行動を明示する形式が多い。
- 見出し構造は媒体依存で差が大きいが、H1時点でテーマを断定的に示す。
- 頻出語は抽象語より、論点の核になる具体語（例: `uuid`, `military`, `verification`）が中心。

## 4) 差分化の提案（twist案3つ、one_sentence案2つ）

### twist案（3つ）

1. **主張即出し + 実証1行**
   - 冒頭1文で結論を断定し、2文目で「なぜ言えるか」をミニ根拠で補強する。
2. **行動導線の二股化**
   - CTAを1つに絞らず、`すぐ試す` と `背景を読む` の2導線を並置して離脱を減らす。
3. **論点キーワード固定表示**
   - 頻出語の核（3語）をヘッダ下に常設して、読み手に記事の焦点を即認識させる。

### one_sentence案（2つ）

1. 「最初の1文で結論、次の1文で根拠まで示すから、読む前に価値がわかる。」
2. 「試す導線と学ぶ導線を同時に置き、速い人も深く知りたい人も取りこぼさない。」

## 5) やらないこと（真似しないポイント）

- 媒体UI由来の見出しやノイズ語をそのまま企画に転写しない（本文論点だけを抽出して使う）。

---

## Validation Update (2026-03-07)

- blocked をスキップして `success_target=3` を満たすまで繰り上げ走査。
- 集計: success=3 / blocked=1 / failed=0 / considered=4（max_candidates=10）

### 対象URL一覧（status付き）
- ok: https://buttondown.com/creativegood/archive/ai-and-the-illegal-war/
- blocked: https://www.science.org/content/article/can-wealthy-family-change-course-deadly-brain-disease
  - reason: title/body/headings に `Just a moment` / `Performing security verification` を検出
- ok: https://github.com/golang/go/issues/62026
- ok: https://blog.katanaquant.com/p/your-llm-doesnt-write-correct-code

### ルール適用メモ
- blocked/failed は記録のみ行い、共通パターン・twist・one_sentence の根拠には不使用。
- 機械利用用の同日JSON: `reports/competitors/competitor_scan_2026-03-07_shortlist.json`
