# ai-dev-exp-control — 運用司令塔

> AIだけで「企画→実装→公開→宣伝」を100本回す実験のコントロールリポジトリ。

---

## クイックスタート（週1起動）

```bash
# 1. WSL / Git Bash を起動
# 2. control repoに移動
cd ~/ai-dev-exp-control

# 3. resume を実行（STATEを読んで自動で続きを処理）
bash scripts/resume.sh
```

これだけで:
- STATE.json から `next_day` を読み取り
- 7本分のDay repoを生成・ビルド・デプロイ
- 各Day repoに `STORY.md` を自動生成（READMEから参照）
- X投稿テキストを生成
- Buffer投入（連携済みなら）
- カタログページを更新

---

## 必須ツール

| ツール | 用途 | インストール |
|--------|------|-------------|
| `bash` | スクリプト実行 | WSL or Git Bash |
| `jq` | JSON操作 | `sudo apt install jq` / `brew install jq` |
| `gh` | GitHub CLI（repo作成・Pages設定） | [cli.github.com](https://cli.github.com/) |
| `node` / `npm` | Viteビルド | [nodejs.org](https://nodejs.org/) |
| `curl` | Buffer API / Make Webhook | 標準搭載 |

---

## 初期設定（初回のみ・人間が実施）

### 1. GitHub認証

```bash
gh auth login
```

### 2. このcontrol repoをGitHubに作成

```bash
cd ai-dev-exp-control
git init
git add -A
git commit -m "init: control repo"
gh repo create ai-dev-exp-control --public --source=. --push
```

### 3. template repoをGitHubに作成

```bash
cd ../ai-dev-exp-template
git init
git add -A
git commit -m "init: template repo"
gh repo create ai-dev-exp-template --public --source=. --push
```

### 4. GitHub Pages設定（control repo）

```bash
gh repo edit ai-dev-exp-control --enable-pages
# Pages source: main branch, /catalog ディレクトリ
# GitHub Settings > Pages から手動で設定してもOK
```

### 5. Buffer投稿スロット設定

1. [Buffer](https://buffer.com) にログイン
2. X（Twitter）アカウントを接続
3. 投稿スケジュールに **7枠** を設定（例: 月〜日 各1回 12:00）
4. Buffer Access Token を取得し、環境変数に設定:
   ```bash
   export BUFFER_ACCESS_TOKEN="your-token-here"
   ```

### 6. Make Webhook（任意）

Make.com でシナリオを作成し、Webhook URLを環境変数に設定:
```bash
export MAKE_WEBHOOK_URL="https://hook.make.com/xxx"
```

---

## ディレクトリ構成

```
ai-dev-exp-control/
├── STATE.json        # 進捗の唯一の正
├── RULES.md          # AI契約ルール
├── CATALOG.md        # 人間向け一覧
├── README.md         # このファイル
├── catalog/
│   ├── index.html    # 100本一覧ページ（Pages公開）
│   ├── catalog.json  # 機械読み一覧
│   └── latest.json   # 最新7本
├── scripts/
│   ├── resume.sh     # 入口
│   ├── run_batch.sh  # バッチ処理（7本）
│   ├── run_day.sh    # 1日分処理
│   └── build_catalog.sh  # カタログ更新
└── schemas/
    ├── state_schema.json
    └── meta_schema.json
```

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `jq: command not found` | `sudo apt install jq` |
| `gh: command not found` | [GitHub CLI インストール](https://cli.github.com/) |
| Buffer投入失敗 | `BUFFER_ACCESS_TOKEN` を確認。無効なら再取得 |
| Day repoのビルド失敗 | STATEでそのDayは未完了のまま。手動で修正後 `resume.sh` |
| 中断した | そのまま `resume.sh` を再実行。STATE.jsonから自動再開 |

---

## 関連リンク

- **カタログページ**: `https://<username>.github.io/ai-dev-exp-control/`
- **テンプレートrepo**: `ai-dev-exp-template`
- **RULES.md**: AI契約ルール全文
