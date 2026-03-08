# Day009-015 UI / mechanic monoculture audit (2026-03-08)

## 対象
- Day009-015 の current 実装（差し替え前の最新版）
- 確認対象: `index.html`, `src/main.js`, `README.md`

## 所見（要約）
- 7本とも **同一レイアウト骨格**（header + 1 textarea + 1 button + 1 output panel）。
- 7本とも **同一操作ループ**（free-text入力 -> ボタン押下 -> text出力）。
- 7本とも **stateが実質無状態**（入力欄 + 一時表示のみ、永続/複数要素状態なし）。
- semantic label（title/family）は変わっているが、interaction/page/output の novelty は低い。

## 評価軸（5=多様, 1=同型）
| day | interaction_archetype | page_archetype | output_shape | state_model | core_loop | reusable scaffold similarity |
|---|---|---|---|---|---|---|
| Day009 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day010 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day011 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day012 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day013 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day014 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |
| Day015 | 1 (single-shot text submit) | 1 (single-column form) | 1 (single text block) | 1 (ephemeral) | 1 | 5 (ほぼ同型) |

## 同型判定の根拠
- `index.html` の主要DOMが全repoで共通:
  - `.app-header`, `.tool-area`, `.input-group`, `textarea#toolInput`, `button#actionBtn`, `div#outputGroup`
- `src/main.js` の制御骨格が全repoで共通:
  - `const actionBtn...`
  - `processInput(input)` の1回実行
  - `showOutput(...)` の同型描画
- READMEの操作手順も「入力 -> 実行 -> 結果確認」の1ループ固定。

## 監査結論
- 現状の課題は semantic novelty 不足ではなく、**interaction / page / output / state の monoculture**。
- 次回再生成では archetype 先行で固定し、同型 scaffold を同一バッチで再利用しない必要がある。
