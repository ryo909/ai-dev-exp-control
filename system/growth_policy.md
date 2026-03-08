# Growth Policy

## 目的
- Growth layer は「作った後にどう刺さるか」を評価し、発信/導線の推奨を返す planning layer。
- 実装品質（quality）や公開整合（portfolio）と分離し、distribution 観点を補完する。

## 何を評価/提案するか
- one-line positioning の強さ
- audience angle（誰向けか）
- X向け hook / note向け切り口
- launch CTA 候補
- showcase slot の押し出し方（showcase_launch_brief）

## 今回やらないこと
- 投稿の自動実行（X/note/Buffer/Make API連携）
- 投稿内容の自動採用
- 本文の強制書き換え

## 入力ソース（best-effort）
- 優先: `plans/next_batch_plan.json`, `reports/showcase/*`, `reports/control_tower/*`, `reports/competitors/*`, `STATE.json`, `catalog/catalog.json`, `CATALOG.md`
- 補助: `reports/portfolio/*`, quality系, THESIS/weekly_run系
- 欠損入力があっても evaluator 全体は止めない。

## 出力構造
- `reports/growth/growth_brief_<YYYY-MM-DD>.json`
- `reports/growth/growth_brief_<YYYY-MM-DD>.md`
- JSONは `summary`, `role_context`, `by_day`, `showcase_launch_brief`, `recommended_growth_actions` を持つ。

## Growth と Portfolio の違い
- Portfolio: README/Pages/catalog整合など「公開物の健全性」
- Growth: 投稿フック/チャネル優先/訴求角度など「伝播戦略」

## Growth と Strategist の違い
- Strategist: 今週の勝ち筋と方針の上位設計
- Growth: その方針を具体的な発信文脈・導線案へ変換する実行前レイヤー

## showcase launch brief の位置づけ
- 7本のうち1本を押し出すときの簡易 launch playbook。
- showcase plan が無ければ inferred と明示して推定する。

## 今後の拡張候補
- Buffer / Make 連携
- post template export（channel別）
- note draft seed 自動生成
- audience segment library
- CTA A/B candidate generation
